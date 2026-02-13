import Foundation

/// Represents a single item (file or directory) in the file tree.
/// Supports lazy loading of directory children for performance.
class FileTreeItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool

    /// Children of a directory. `nil` for files, empty array for unexpanded directories.
    @Published var children: [FileTreeItem]?

    /// Whether this directory node is expanded in the UI.
    @Published var isExpanded: Bool = false

    /// Directories to skip when scanning.
    private static let ignoredDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
    ]

    /// File names to skip when scanning.
    private static let ignoredFileNames: Set<String> = [
        ".DS_Store",
    ]

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        self.children = isDir.boolValue ? [] : nil
    }

    /// Loads direct children of this directory from the file system.
    /// Sorts directories first, then alphabetically by name.
    /// Shows hidden files (dotfiles) but filters out .git, node_modules, .DS_Store, etc.
    func loadChildren() {
        guard isDirectory else { return }

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            children = []
            return
        }

        children = urls
            .filter {
                let name = $0.lastPathComponent
                if Self.ignoredFileNames.contains(name) { return false }
                if Self.ignoredDirectoryNames.contains(name) { return false }
                return true
            }
            .map { FileTreeItem(url: $0) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Builds the first level of the file tree from a root directory URL.
    /// Runs on a background thread to avoid blocking the UI.
    static func buildTreeAsync(from rootURL: URL, completion: @escaping ([FileTreeItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let root = FileTreeItem(url: rootURL)
            root.loadChildren()
            let items = root.children ?? []
            DispatchQueue.main.async {
                completion(items)
            }
        }
    }
}
