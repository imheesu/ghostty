import SwiftUI
import AppKit

/// A file picker sidebar that shows a tree view of the file system.
/// Follows VS Code-style explorer layout: header with close button, scrollable tree below.
struct FilePickerView: View {
    @ObservedObject var editorState: EditorState
    let onFileSelected: (URL) -> Void
    let onClose: () -> Void

    @State private var treeItems: [FileTreeItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editorState.rootDirectory.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close file explorer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File tree
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
            } else if treeItems.isEmpty {
                VStack {
                    Spacer()
                    Text("No files")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }
            } else {
                List {
                    ForEach(treeItems) { item in
                        FileTreeRow(item: item, onFileSelected: handleFileSelected)
                    }
                }
                .listStyle(.sidebar)
            }

            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
            }
        }
        .frame(minWidth: 150, idealWidth: 250)
        .background(.regularMaterial)
        .onAppear {
            FileTreeItem.buildTreeAsync(from: editorState.rootDirectory) { items in
                treeItems = items
                isLoading = false
            }
        }
    }

    /// Maximum file size (10 MB) to prevent OOM when opening very large files.
    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    private func handleFileSelected(_ url: URL) {
        // Check file size before reading to prevent OOM
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attrs[.size] as? UInt64, fileSize > Self.maxFileSize {
                errorMessage = "File too large (\(fileSize / 1_048_576) MB). Max: 10 MB."
                return
            }
        } catch {
            errorMessage = "Cannot read file attributes: \(error.localizedDescription)"
            return
        }

        // Read file on a background thread to avoid blocking the UI
        let fileURL = url
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: fileURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        errorMessage = "Binary file cannot be opened as text."
                    }
                    return
                }
                DispatchQueue.main.async {
                    errorMessage = nil
                    let fileInfo = EditorState.FileInfo(url: fileURL, content: content)
                    editorState.mode = .editing(fileInfo)
                    onFileSelected(fileURL)
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to read: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// A single row in the file tree. Recursively renders children for directories.
struct FileTreeRow: View {
    @ObservedObject var item: FileTreeItem
    let onFileSelected: (URL) -> Void

    var body: some View {
        if item.isDirectory {
            DisclosureGroup(isExpanded: $item.isExpanded) {
                if let children = item.children {
                    ForEach(children) { child in
                        FileTreeRow(item: child, onFileSelected: onFileSelected)
                    }
                }
            } label: {
                Label {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    fileIcon(for: item.url)
                }
            }
            .onChange(of: item.isExpanded) { expanded in
                if expanded, let children = item.children, children.isEmpty {
                    item.loadChildren()
                }
            }
        } else {
            Button(action: { onFileSelected(item.url) }) {
                Label {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    fileIcon(for: item.url)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func fileIcon(for url: URL) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 16, height: 16)
    }
}
