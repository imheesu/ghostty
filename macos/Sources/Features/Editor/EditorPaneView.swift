import SwiftUI

/// Container view for the editor that provides a thin header bar with
/// breadcrumb path navigation, save status, and a close button.
struct EditorPaneView: View {
    @ObservedObject var editorState: EditorState
    let surfaceView: Ghostty.SurfaceView
    let editorConfig: EditorConfig
    let onClose: () -> Void

    @State private var isHovering: Bool = false
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable {
        case idle
        case saved
        case failed(String)
    }

    var body: some View {
        if case .editing(let fileInfo) = editorState.mode {
            VStack(spacing: 0) {
                // Thin header bar
                HStack(spacing: 4) {
                    breadcrumb(for: fileInfo)

                    Spacer()

                    // Save status feedback
                    switch saveStatus {
                    case .saved:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .transition(.opacity)
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .help(msg)
                    case .idle:
                        EmptyView()
                    }

                    // Modification indicator
                    if fileInfo.isModified {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 6, height: 6)
                    }

                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .opacity(isHovering ? 1.0 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHovering = hovering
                    }
                    .help("Close editor")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)

                // Editor
                EditorWebView(
                    fileInfo: fileInfo,
                    surfaceView: surfaceView,
                    editorConfig: editorConfig,
                    onSave: { content in saveFile(content: content, to: fileInfo.url) },
                    onAutoSave: { content in autoSaveFile(content: content, to: fileInfo.url) },
                    onClose: onClose,
                    onSwitchMode: fileInfo.isMarkdown ? { content in
                        // Toggle between BlockNote ↔ Monaco, preserving content
                        if case .editing(var fi) = editorState.mode {
                            fi.content = content
                            fi.markdownViewMode = (fi.markdownViewMode == .blocknote) ? .editor : .blocknote
                            editorState.mode = .editing(fi)
                        }
                    } : nil
                )
            }
        }
    }

    /// Builds a breadcrumb view showing the relative path from rootDirectory to the file.
    /// Each path component is separated by a chevron; the last component (filename) is primary-colored.
    @ViewBuilder
    private func breadcrumb(for fileInfo: EditorState.FileInfo) -> some View {
        let components = relativePath(from: editorState.rootDirectory, to: fileInfo.url)

        HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
                Text(component)
                    .font(.system(size: 12))
                    .foregroundColor(index == components.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Returns the path components of `file` relative to `root`.
    /// If the file is not under root, returns just the filename.
    private func relativePath(from root: URL, to file: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path

        if filePath.hasPrefix(rootPath) {
            var relative = String(filePath.dropFirst(rootPath.count))
            // Remove leading slash if present
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            let components = relative.split(separator: "/").map(String.init)
            return components.isEmpty ? [file.lastPathComponent] : components
        }
        return [file.lastPathComponent]
    }

    private func saveFile(content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            saveStatus = .saved
            // Auto-dismiss success indicator after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if saveStatus == .saved {
                    saveStatus = .idle
                }
            }
        } catch {
            saveStatus = .failed(error.localizedDescription)
        }
    }

    /// Silent auto-save: writes to disk without UI feedback.
    private func autoSaveFile(content: String, to url: URL) {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
