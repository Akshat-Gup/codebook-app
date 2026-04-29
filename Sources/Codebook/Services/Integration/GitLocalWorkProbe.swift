import Foundation

/// Read-only git probes for local work that is not on the configured upstream yet.
enum GitLocalWorkProbe {
    private static func git(_ arguments: [String]) -> ShellResult? {
        try? Shell.run("/usr/bin/git", arguments: arguments)
    }

    static func isInsideWorkTree(gitRoot: String) -> Bool {
        guard let result = git(["-C", gitRoot, "rev-parse", "--is-inside-work-tree"]),
              result.status == 0 else { return false }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func hasUncommittedChanges(gitRoot: String) -> Bool {
        guard let result = git(["-C", gitRoot, "status", "--short", "--untracked-files=all"]),
              result.status == 0 else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Commits reachable from `HEAD` but not from `@{upstream}` (requires upstream to exist).
    static func unpushedCommitCount(gitRoot: String) -> Int {
        guard let upstream = git(["-C", gitRoot, "rev-parse", "--verify", "@{upstream}"]),
              upstream.status == 0 else { return 0 }
        guard let count = git(["-C", gitRoot, "rev-list", "--count", "@{upstream}..HEAD"]),
              count.status == 0 else { return 0 }
        return Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func hasWorkNotYetOnUpstream(gitRoot: String) -> Bool {
        guard isInsideWorkTree(gitRoot: gitRoot) else { return false }
        return hasUncommittedChanges(gitRoot: gitRoot) || unpushedCommitCount(gitRoot: gitRoot) > 0
    }
}
