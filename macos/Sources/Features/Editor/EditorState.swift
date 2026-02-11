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

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.mode = .filePicker
    }
}
