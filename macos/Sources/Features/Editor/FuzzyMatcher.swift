import Foundation

/// Pure Swift fuzzy matching algorithm for file path search.
/// Matches characters sequentially with scoring bonuses for consecutive matches,
/// word boundaries, and path start positions.
enum FuzzyMatcher {
    struct Result {
        let path: String
        let score: Int
        /// Indices of matched characters in the path string (for highlighting).
        let matchedIndices: [Int]
    }

    /// Matches a query against a list of file paths and returns the top results.
    /// - Parameters:
    ///   - query: The search string (case-insensitive).
    ///   - paths: File paths relative to the root directory.
    ///   - maxResults: Maximum number of results to return.
    /// - Returns: Sorted results with highest scores first.
    static func match(query: String, paths: [String], maxResults: Int = 50) -> [Result] {
        let queryChars = Array(query.lowercased())
        guard !queryChars.isEmpty else { return [] }

        var results: [Result] = []
        results.reserveCapacity(min(paths.count, maxResults * 2))

        for path in paths {
            // Try matching against the filename first, then the full path.
            let filename = (path as NSString).lastPathComponent
            let filenameResult = score(query: queryChars, target: filename)
            let pathResult = score(query: queryChars, target: path)

            // Use the better score. For filename matches, translate indices to path offsets.
            let best: (score: Int, indices: [Int])?
            if let fr = filenameResult, let pr = pathResult {
                if fr.score >= pr.score {
                    let filenameOffset = path.count - filename.count
                    best = (fr.score, fr.indices.map { $0 + filenameOffset })
                } else {
                    best = pr
                }
            } else if let fr = filenameResult {
                let filenameOffset = path.count - filename.count
                best = (fr.score, fr.indices.map { $0 + filenameOffset })
            } else if let pr = pathResult {
                best = pr
            } else {
                best = nil
            }

            if let best {
                // Shorter paths get a small bonus (prefer less nested files).
                let lengthPenalty = path.count / 10
                results.append(Result(
                    path: path,
                    score: best.score - lengthPenalty,
                    matchedIndices: best.indices
                ))
            }
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(maxResults))
    }

    /// Scores a query against a single target string.
    /// Returns nil if the query doesn't match.
    private static func score(query: [Character], target: String) -> (score: Int, indices: [Int])? {
        let targetChars = Array(target.lowercased())
        let targetOriginal = Array(target)
        guard targetChars.count >= query.count else { return nil }

        var totalScore = 0
        var matchedIndices: [Int] = []
        matchedIndices.reserveCapacity(query.count)
        var targetIndex = 0
        var prevMatchIndex = -2 // -2 so first match isn't treated as consecutive
        var queryIndex = 0

        while queryIndex < query.count && targetIndex < targetChars.count {
            if query[queryIndex] == targetChars[targetIndex] {
                var charScore = 1

                // Consecutive match bonus
                if targetIndex == prevMatchIndex + 1 {
                    charScore += 4
                }

                // Word boundary bonus (after /, ., -, _)
                if targetIndex > 0 {
                    let prev = targetChars[targetIndex - 1]
                    if prev == "/" || prev == "." || prev == "-" || prev == "_" {
                        charScore += 3
                    }
                    // camelCase transition bonus
                    if targetOriginal[targetIndex].isUppercase && !targetOriginal[targetIndex - 1].isUppercase {
                        charScore += 2
                    }
                }

                // String start bonus
                if targetIndex == 0 {
                    charScore += 5
                }

                totalScore += charScore
                matchedIndices.append(targetIndex)
                prevMatchIndex = targetIndex
                queryIndex += 1
            } else if queryIndex > 0 {
                // Gap penalty
                totalScore -= 1
            }
            targetIndex += 1
        }

        // All query characters must be matched.
        guard queryIndex == query.count else { return nil }
        return (totalScore, matchedIndices)
    }
}
