import Foundation

/// Parses `git show --shortstat` output for per-commit line/file stats.
enum GitCommitDiffLookup: Sendable {
    struct Stats: Hashable, Sendable {
        var filesChanged: Int?
        var insertions: Int
        var deletions: Int
    }

    private static let batchSize = 128

    static func stats(gitRoot: String, sha: String) -> Stats? {
        statsByCommit(gitRoot: gitRoot, shas: [sha])[normalizedSHA(sha)]
    }

    static func statsByCommit(gitRoot: String, shas: [String]) -> [String: Stats] {
        let trimmedRoot = gitRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedShas = Array(Set(shas.map(normalizedSHA(_:)).filter { !$0.isEmpty }))
        guard !trimmedRoot.isEmpty, !normalizedShas.isEmpty else { return [:] }

        var allStats: [String: Stats] = [:]
        allStats.reserveCapacity(normalizedShas.count)

        var start = 0
        while start < normalizedShas.count {
            let end = min(start + batchSize, normalizedShas.count)
            let batch = Array(normalizedShas[start..<end])
            let arguments = ["git", "-C", trimmedRoot, "log", "--shortstat", "--format=commit:%H", "--no-walk"] + batch
            guard let result = try? Shell.run(arguments: arguments, timeout: 5), result.status == 0 else {
                start = end
                continue
            }

            allStats.merge(parseStatsByCommit(result.stdout), uniquingKeysWith: { _, new in new })
            start = end
        }

        return allStats
    }

    static func parseShortstatLine(_ line: String) -> Stats? {
        var filesChanged: Int?
        var insertions = 0
        var deletions = 0
        let chunks = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for chunk in chunks where !chunk.isEmpty {
            if chunk.contains("file"), chunk.contains("changed") {
                filesChanged = leadingInt(chunk)
            } else if chunk.contains("insertion") {
                insertions = leadingInt(chunk) ?? 0
            } else if chunk.contains("deletion") {
                deletions = leadingInt(chunk) ?? 0
            }
        }
        if filesChanged == nil, insertions == 0, deletions == 0 {
            return nil
        }
        return Stats(filesChanged: filesChanged, insertions: insertions, deletions: deletions)
    }

    static func parseStatsByCommit(_ output: String) -> [String: Stats] {
        var statsByCommit: [String: Stats] = [:]
        var currentSHA: String?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let sha = line.stripPrefix("commit:") {
                currentSHA = normalizedSHA(sha)
                continue
            }

            guard let currentSHA, let stats = parseShortstatLine(line) else { continue }
            statsByCommit[currentSHA] = stats
        }

        return statsByCommit
    }

    private static func leadingInt(_ s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }

    private static func normalizedSHA(_ sha: String) -> String {
        sha.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
