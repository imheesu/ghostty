import Foundation

/// Watches a single file for external modifications using kqueue (DispatchSourceFileSystemObject).
/// Provides debouncing (100ms) and self-write suppression to avoid reloading on internal saves.
final class FileWatcher {
    typealias ChangeHandler = () -> Void

    private let url: URL
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "com.ghosttown.filewatcher", qos: .utility)

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    /// Counter for suppressing events triggered by internal saves.
    /// Call `suppressNext()` before each internal write.
    private var suppressCount: Int = 0

    /// Whether the watcher is actively monitoring.
    private(set) var isWatching = false

    /// Reconnection state for handling delete/rename (atomic writes).
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectAttempts: Int = 0
    private static let maxReconnectAttempts = 10
    private static let reconnectInterval: TimeInterval = 1.0

    init(url: URL, onChange: @escaping ChangeHandler) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func start() {
        guard !isWatching else { return }
        isWatching = true
        attachSource()
    }

    func stop() {
        isWatching = false
        cancelReconnect()
        detachSource()
    }

    /// Call before an internal save to suppress the next file-change event.
    func suppressNext() {
        queue.async { [weak self] in
            self?.suppressCount += 1
        }
    }

    // MARK: - Source Management

    private func attachSource() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File might not exist yet; attempt reconnection.
            scheduleReconnect()
            return
        }
        fileDescriptor = fd

        let events: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: events,
            queue: queue
        )

        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = src.data
            if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
                // The inode is gone (atomic write, git checkout, etc.).
                // Detach current source and try to reattach to the new file.
                self.detachSource()
                self.scheduleReconnect()
            } else if event.contains(.write) {
                self.handleWriteEvent()
            }
        }

        src.setCancelHandler { [fd] in
            close(fd)
        }

        source = src
        src.resume()
    }

    private func detachSource() {
        debounceWork?.cancel()
        debounceWork = nil

        if let src = source {
            source = nil
            src.cancel()
            // fd is closed in the cancel handler
            fileDescriptor = -1
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Write Event Handling with Debounce

    private func handleWriteEvent() {
        // Cancel any pending debounce to coalesce rapid events.
        debounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Check if this event should be suppressed (internal save).
            if self.suppressCount > 0 {
                self.suppressCount -= 1
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.onChange()
            }
        }

        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        cancelReconnect()
        guard isWatching else { return }
        reconnectAttempts = 0

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.reconnectInterval,
            repeating: Self.reconnectInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isWatching else {
                self?.cancelReconnect()
                return
            }
            self.reconnectAttempts += 1

            if self.reconnectAttempts > Self.maxReconnectAttempts {
                self.cancelReconnect()
                return
            }

            // Try to open the file again.
            let fd = open(self.url.path, O_EVTONLY)
            if fd >= 0 {
                close(fd)
                // File exists again — reattach and notify about the change.
                self.cancelReconnect()
                self.attachSource()

                DispatchQueue.main.async { [weak self] in
                    self?.onChange()
                }
            }
        }

        reconnectTimer = timer
        timer.resume()
    }

    private func cancelReconnect() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectAttempts = 0
    }
}
