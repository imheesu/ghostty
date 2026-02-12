import Foundation

/// Asynchronously scans a directory tree and returns all file paths relative to the root.
/// Prefers `git ls-files` for speed and .gitignore support, with a FileManager fallback.
enum FileScanner {
    /// Maximum number of files to index.
    private static let maxFiles = 50_000

    /// Directories to skip when scanning (fallback only).
    private static let ignoredDirectoryNames: Set<String> = [
        ".git",
    ]

    /// File names to exclude from search results (fallback only).
    private static let ignoredFileNames: Set<String> = [
        ".DS_Store",
    ]

    /// Scans the directory at `root` and returns relative file paths.
    /// Runs on a background thread via async/await.
    static func scan(root: URL) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let paths = scanWithGit(root: root) ?? scanSync(root: root)
                continuation.resume(returning: paths)
            }
        }
    }

    /// Fast path: use `git ls-files` to list files respecting .gitignore.
    /// Returns nil if the directory is not a git repository.
    private static func scanWithGit(root: URL) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files", "--cached", "--others", "--exclude-standard"]
        process.currentDirectoryURL = root

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var paths: [String] = []
        paths.reserveCapacity(1024)

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if paths.count >= maxFiles { break }
            paths.append(String(line))
        }

        return paths
    }

    /// Fallback: scan using FileManager when not in a git repository.
    private static func scanSync(root: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
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

            // Skip ignored file names.
            if ignoredFileNames.contains(name) { continue }

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
