import Foundation
import Combine

/// Manages the state of the in-pane editor feature.
/// Tracks the current mode (file picker or editing) and the root directory for file browsing.
class EditorState: ObservableObject {
    /// Which sub-editor to use for markdown files.
    enum MarkdownViewMode: Equatable {
        case blocknote  // BlockNote block editor (default for markdown)
        case editor     // Monaco text editor
    }

    /// The current mode of the editor.
    enum Mode: Equatable {
        /// Showing the file picker sidebar alongside the terminal.
        case filePicker
        /// Editing a file, replacing the terminal view entirely.
        case editing(FileInfo)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.filePicker, .filePicker):
                return true
            case (.editing(let a), .editing(let b)):
                return a.url == b.url
            default:
                return false
            }
        }
    }

    /// Represents an open file being edited.
    struct FileInfo: Equatable {
        /// The file URL on disk.
        let url: URL
        /// The file content as a string.
        var content: String
        /// Whether the content has been modified since last save.
        var isModified: Bool = false
        /// Which view mode to use for markdown files (ignored for non-markdown).
        var markdownViewMode: MarkdownViewMode = .blocknote
        /// Monotonically increasing version counter bumped on external file changes.
        /// Used by EditorWebView.updateNSView to detect when content should be refreshed.
        var contentVersion: UInt64 = 0

        /// True if the file is a Markdown file based on its extension.
        var isMarkdown: Bool {
            let ext = url.pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }
    }

    /// The current editor mode.
    @Published var mode: Mode

    /// The root directory for the file tree.
    let rootDirectory: URL

    /// Watches the currently edited file for external changes.
    private var fileWatcher: FileWatcher?

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.mode = .filePicker
    }

    deinit {
        stopWatching()
    }

    // MARK: - File Watching

    /// Starts watching the currently edited file for external modifications.
    func startWatching() {
        guard case .editing(let fileInfo) = mode else { return }
        stopWatching()

        fileWatcher = FileWatcher(url: fileInfo.url) { [weak self] in
            self?.handleExternalChange()
        }
        fileWatcher?.start()
    }

    /// Stops and releases the file watcher.
    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Call before an internal save (Cmd+S or auto-save) to prevent the
    /// resulting file-system event from triggering a reload.
    func suppressFileWatcherEvent() {
        fileWatcher?.suppressNext()
    }

    /// Called when the file watcher detects an external change.
    /// Reads the file from disk and, if the content differs, updates the mode
    /// with a bumped contentVersion so EditorWebView refreshes.
    private func handleExternalChange() {
        guard case .editing(var fileInfo) = mode else { return }

        guard let newContent = try? String(contentsOf: fileInfo.url, encoding: .utf8) else { return }

        // Only reload if content actually differs.
        guard newContent != fileInfo.content else { return }

        fileInfo.content = newContent
        fileInfo.contentVersion += 1
        fileInfo.isModified = false
        mode = .editing(fileInfo)
    }
}
