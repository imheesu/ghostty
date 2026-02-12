import Foundation

/// Asynchronously scans a directory tree and returns all file paths relative to the root.
/// Uses FileManager.enumerator for efficient recursive traversal.
enum FileScanner {
    /// Maximum number of files to index.
    private static let maxFiles = 50_000

    /// Directories to skip when scanning (matches FileTreeItem.ignoredDirectoryNames).
    private static let ignoredDirectoryNames: Set<String> = [
        "node_modules", ".git", ".svn", ".hg",
        "dist", "build", ".build", "target",
        "venv", ".venv", "__pycache__", ".tox",
        "vendor", "Pods", ".pods",
        "DerivedData", ".xcodeproj", ".xcworkspace",
        "zig-cache", "zig-out",
    ]

    /// Scans the directory at `root` and returns relative file paths.
    /// Runs on a background thread via async/await.
    static func scan(root: URL) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let paths = scanSync(root: root)
                continuation.resume(returning: paths)
            }
        }
    }

    private static func scanSync(root: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPath = root.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var paths: [String] = []
        paths.reserveCapacity(1024)

        while let url = enumerator.nextObject() as? URL {
            if paths.count >= maxFiles { break }

            let name = url.lastPathComponent

            // Check if this is a directory we should skip.
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                if ignoredDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            // Build relative path.
            let fullPath = url.standardizedFileURL.path
            if fullPath.hasPrefix(rootPrefix) {
                paths.append(String(fullPath.dropFirst(rootPrefix.count)))
            } else {
                paths.append(name)
            }
        }

        return paths
    }
}
