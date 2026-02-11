import SwiftUI
import WebKit

/// Wraps a WKWebView that hosts Monaco Editor or BlockNote (for markdown files).
/// Communicates with JavaScript through message handlers for save/close/ready/switchMode events.
struct EditorWebView: NSViewRepresentable {
    let fileInfo: EditorState.FileInfo
    let surfaceView: Ghostty.SurfaceView
    let onSave: (String) -> Void
    let onAutoSave: ((String) -> Void)?
    let onClose: () -> Void
    let onSwitchMode: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fileInfo: fileInfo,
            onSave: onSave,
            onAutoSave: onAutoSave,
            onClose: onClose,
            onSwitchMode: onSwitchMode
        )
    }

    func makeNSView(context: Context) -> EditorWKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // Register message handlers for JS -> Swift communication.
        // Use a weak wrapper to avoid retain cycle: WKUserContentController
        // strongly retains its message handlers.
        let handler = WeakScriptMessageHandler(delegate: context.coordinator)
        controller.add(handler, name: "save")
        controller.add(handler, name: "autoSave")
        controller.add(handler, name: "close")
        controller.add(handler, name: "ready")
        controller.add(handler, name: "switchMode")
        config.userContentController = controller

        // Note: we do NOT set allowFileAccessFromFileURLs; content is passed via JS bridge.
        // loadFileURL(..., allowingReadAccessTo:) already grants access to the resource dir.

        let webView = EditorWKWebView(frame: .zero, configuration: config)
        webView.surfaceView = surfaceView
        webView.underPageBackgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.currentViewMode = fileInfo.isMarkdown ? fileInfo.markdownViewMode : .editor

        // Load the appropriate HTML based on file type and view mode
        let htmlURL = Self.htmlURL(for: fileInfo)
        if let htmlURL {
            let resourceDir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
        } else {
            webView.loadHTMLString(
                "<html><body style='color:#888;font-family:system-ui;padding:2em;'>"
                + "Editor resources not found.</body></html>",
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ webView: EditorWKWebView, context: Context) {
        let coordinator = context.coordinator

        // Detect view mode change (e.g. Cmd+E toggled between BlockNote ↔ Monaco)
        let newViewMode = fileInfo.isMarkdown ? fileInfo.markdownViewMode : .editor
        if coordinator.currentViewMode != newViewMode {
            coordinator.currentViewMode = newViewMode
            coordinator.isEditorReady = false
            coordinator.fileInfo = fileInfo

            if let htmlURL = Self.htmlURL(for: fileInfo) {
                let resourceDir = htmlURL.deletingLastPathComponent()
                webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
            }
            return
        }

        // If the file changed, update the coordinator and push new content
        if coordinator.fileInfo.url != fileInfo.url {
            coordinator.fileInfo = fileInfo
            if coordinator.isEditorReady {
                coordinator.sendContentToEditor()
            }
        }
    }

    /// Clean up message handlers when the view is removed to prevent leaks.
    static func dismantleNSView(_ webView: EditorWKWebView, coordinator: Coordinator) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "save")
        controller.removeScriptMessageHandler(forName: "autoSave")
        controller.removeScriptMessageHandler(forName: "close")
        controller.removeScriptMessageHandler(forName: "ready")
        controller.removeScriptMessageHandler(forName: "switchMode")
        coordinator.webView = nil
    }

    // MARK: - HTML Resource Location

    /// Returns the appropriate HTML URL based on file type and markdown view mode.
    private static func htmlURL(for fileInfo: EditorState.FileInfo) -> URL? {
        if fileInfo.isMarkdown && fileInfo.markdownViewMode == .blocknote {
            return findBlockNoteHTML()
        }
        return findEditorHTML()
    }

    /// Searches for editor.html in multiple locations:
    /// 1. App bundle with subdirectory (for folder reference bundling)
    /// 2. App bundle root (for flat file system sync bundling)
    /// 3. Source tree (for development with #filePath)
    static func findEditorHTML() -> URL? {
        if let url = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "EditorResources") {
            return url
        }
        if let url = Bundle.main.url(forResource: "editor", withExtension: "html") {
            return url
        }
        // Fallback: source tree for development
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("editor.html")
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            return sourceDir
        }
        return nil
    }

    /// Searches for blocknote.html using the same pattern as findEditorHTML.
    static func findBlockNoteHTML() -> URL? {
        if let url = Bundle.main.url(forResource: "blocknote", withExtension: "html", subdirectory: "EditorResources") {
            return url
        }
        if let url = Bundle.main.url(forResource: "blocknote", withExtension: "html") {
            return url
        }
        // Fallback: source tree for development
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("blocknote.html")
        if FileManager.default.fileExists(atPath: sourceDir.path) {
            return sourceDir
        }
        return nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        var fileInfo: EditorState.FileInfo
        let onSave: (String) -> Void
        let onAutoSave: ((String) -> Void)?
        let onClose: () -> Void
        let onSwitchMode: ((String) -> Void)?
        weak var webView: WKWebView?

        /// Tracks whether the editor has sent the "ready" message.
        var isEditorReady = false

        /// Tracks the current view mode to detect changes in updateNSView.
        var currentViewMode: EditorState.MarkdownViewMode = .editor

        init(
            fileInfo: EditorState.FileInfo,
            onSave: @escaping (String) -> Void,
            onAutoSave: ((String) -> Void)?,
            onClose: @escaping () -> Void,
            onSwitchMode: ((String) -> Void)?
        ) {
            self.fileInfo = fileInfo
            self.onSave = onSave
            self.onAutoSave = onAutoSave
            self.onClose = onClose
            self.onSwitchMode = onSwitchMode
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // WKScriptMessageHandler callbacks are already on the main thread
            switch message.name {
            case "ready":
                isEditorReady = true
                initializeEditor()

            case "save":
                if let body = message.body as? [String: Any],
                   let content = body["content"] as? String {
                    onSave(content)
                }

            case "autoSave":
                if let body = message.body as? [String: Any],
                   let content = body["content"] as? String {
                    onAutoSave?(content)
                }

            case "switchMode":
                if let body = message.body as? [String: Any],
                   let content = body["content"] as? String {
                    onSwitchMode?(content)
                }

            case "close":
                onClose()

            default:
                break
            }
        }

        private func initializeEditor() {
            // BlockNote handles its own initialization; only Monaco needs initEditor/setContent.
            if currentViewMode == .blocknote {
                sendMarkdownToBlockNote()
                return
            }

            let ext = fileInfo.url.pathExtension
            let languageId = monacoLanguageId(for: ext)
            let editorType = fileInfo.isMarkdown ? "markdown" : "monaco"

            // JSON-encode parameters to prevent injection
            guard let typeData = try? JSONEncoder().encode(editorType),
                  let typeStr = String(data: typeData, encoding: .utf8),
                  let langData = try? JSONEncoder().encode(languageId),
                  let langStr = String(data: langData, encoding: .utf8) else {
                return
            }
            callJS("initEditor(\(typeStr), \(langStr))")
            sendContentToEditor()
        }

        /// Sends the current file content to the editor via JavaScript.
        func sendContentToEditor() {
            guard isEditorReady else { return }

            if currentViewMode == .blocknote {
                sendMarkdownToBlockNote()
                return
            }

            guard let jsonData = try? JSONEncoder().encode(fileInfo.content),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            callJS("setContent(\(jsonString))")
        }

        /// Sends markdown content to BlockNote via its JS bridge.
        private func sendMarkdownToBlockNote() {
            guard isEditorReady else { return }
            guard let jsonData = try? JSONEncoder().encode(fileInfo.content),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            callJS("setMarkdown(\(jsonString))")
        }

        private func callJS(_ script: String) {
            webView?.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("[EditorWebView] JS error: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// A weak wrapper around WKScriptMessageHandler to prevent retain cycles.
/// WKUserContentController strongly retains its message handlers, so using
/// this wrapper allows the Coordinator to be deallocated properly.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
