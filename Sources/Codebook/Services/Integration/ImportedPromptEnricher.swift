import Foundation

struct ImportedPromptEnricher {
    private static let metadataCache = ProjectMetadataCache()
    private static let gitProbeTimeout: TimeInterval = 2
    private static let gitHistoryTimeout: TimeInterval = 5
    private let fileManager = FileManager.default
    private let calendar = Calendar.current
    private let pathResolver = ProjectPathResolver()

    func enrich(_ prompts: [ImportedPrompt]) -> [ImportedPrompt] {
        let resolvedProjectPaths = resolvedProjectPaths(for: prompts)
        let projectMetadata = buildProjectMetadata(for: resolvedProjectPaths.values)
        let contextPreferredCommitSHAs = preferredCommitSHAsByContext(
            from: prompts,
            resolvedProjectPaths: resolvedProjectPaths,
            projectMetadata: projectMetadata
        )

        let enriched = prompts.map { prompt in
            var row = prompt
            let resolvedProjectPath = prompt.projectPath.flatMap { resolvedProjectPaths[normalizedRawProjectPath($0)] }
            let metadata = resolvedProjectPath.flatMap { projectMetadata[$0] }
            let projectName = metadata?.displayName ?? prompt.projectName

            row.projectName = projectName
            row.projectKey = metadata?.projectKey ?? prompt.projectKey
            row.gitRoot = metadata?.gitRoot
            row.tags = PromptTagger.tags(for: row, projectName: projectName)
            row.commitOrphaned = false
            row.commitInsertions = nil
            row.commitDeletions = nil
            row.commitFilesChanged = nil

            if let meta = metadata {
                let contextPreferredCommitSHA = contextKey(for: prompt).flatMap { contextPreferredCommitSHAs[$0] }
                let preferredCommitSHA = prompt.commitSHA ?? contextPreferredCommitSHA
                let explicitCommit = prompt.commitSHA.flatMap { commit(matching: $0, in: meta.commits) }

                if let explicitCommit, explicitCommit.date >= prompt.capturedAt {
                    apply(commit: explicitCommit, confidence: .high, to: &row)
                } else if let explicitCommit, explicitCommit.date < prompt.capturedAt {
                    clearCommitLink(on: &row)
                } else if prompt.commitSHA != nil, explicitCommit == nil, !meta.commits.isEmpty {
                    row.commitOrphaned = true
                } else if let commit = associatedCommit(
                    for: prompt.capturedAt,
                    in: meta.commits,
                    preferredCommitSHA: preferredCommitSHA
                ) {
                    apply(commit: commit.commit, confidence: commit.confidence, to: &row)
                }
            }

            return row
        }

        let diffCache = commitDiffCache(for: enriched)
        return enriched.map { prompt in
            guard let root = prompt.gitRoot,
                  let sha = prompt.commitSHA,
                  !prompt.commitOrphaned
            else {
                return prompt
            }
            let key = Self.cacheKey(gitRoot: root, sha: sha)
            guard let stats = diffCache[key] else { return prompt }
            var row = prompt
            row.commitInsertions = stats.insertions
            row.commitDeletions = stats.deletions
            row.commitFilesChanged = stats.filesChanged
            return row
        }
    }

    private func commitDiffCache(for prompts: [ImportedPrompt]) -> [String: GitCommitDiffLookup.Stats] {
        var shasByRoot: [String: Set<String>] = [:]
        for prompt in prompts {
            guard let root = prompt.gitRoot,
                  let sha = prompt.commitSHA,
                  !prompt.commitOrphaned
            else {
                continue
            }
            shasByRoot[root, default: []].insert(sha)
        }

        guard !shasByRoot.isEmpty else { return [:] }

        let rootEntries = Array(shasByRoot)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = min(rootEntries.count, ProcessInfo.processInfo.activeProcessorCount)
        let cache = LockedDictionary<String, GitCommitDiffLookup.Stats>(
            minimumCapacity: shasByRoot.reduce(0) { $0 + $1.value.count }
        )

        for (root, shas) in rootEntries {
            queue.addOperation {
                let statsByCommit = Self.metadataCache.diffStats(for: root, shas: Array(shas))
                var localPairs: [(String, GitCommitDiffLookup.Stats)] = []
                localPairs.reserveCapacity(shas.count)
                for sha in shas {
                    let normalizedSHA = sha.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard let stats = statsByCommit[normalizedSHA] else { continue }
                    localPairs.append((Self.cacheKey(gitRoot: root, sha: sha), stats))
                }

                guard !localPairs.isEmpty else { return }
                cache.merge(localPairs)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return cache.snapshot()
    }

    private static func cacheKey(gitRoot: String, sha: String) -> String {
        "\(gitRoot)\u{1e}\(sha)"
    }

    private func preferredCommitSHAsByContext(
        from prompts: [ImportedPrompt],
        resolvedProjectPaths: [String: String],
        projectMetadata: [String: ProjectMetadata]
    ) -> [String: String] {
        var bestByContext: [String: (sha: String, commitDate: Date)] = [:]

        for prompt in prompts {
            guard let key = contextKey(for: prompt),
                  let sha = prompt.commitSHA,
                  let rawProjectPath = prompt.projectPath,
                  let resolvedProjectPath = resolvedProjectPaths[normalizedRawProjectPath(rawProjectPath)],
                  let metadata = projectMetadata[resolvedProjectPath],
                  let commit = commit(matching: sha, in: metadata.commits),
                  commit.date >= prompt.capturedAt
            else {
                continue
            }

            if let existing = bestByContext[key], existing.commitDate >= commit.date {
                continue
            }
            bestByContext[key] = (commit.sha, commit.date)
        }

        return bestByContext.mapValues(\.sha)
    }

    private func contextKey(for prompt: ImportedPrompt) -> String? {
        guard let sourceContextID = prompt.sourceContextID, !sourceContextID.isEmpty else { return nil }
        return "\(prompt.provider.rawValue)|\(prompt.projectKey)|\(sourceContextID)"
    }

    private func resolvedProjectPaths(for prompts: [ImportedPrompt]) -> [String: String] {
        let rawPaths = Set(prompts.compactMap { prompt in
            prompt.projectPath.flatMap(normalizedRawProjectPath(_:))
        })
        var resolvedByRawPath: [String: String] = [:]
        for rawPath in rawPaths {
            if let resolved = normalizedProjectPath(from: rawPath) {
                resolvedByRawPath[rawPath] = resolved
            }
        }
        return resolvedByRawPath
    }

    private func buildProjectMetadata(for resolvedPaths: Dictionary<String, String>.Values) -> [String: ProjectMetadata] {
        let paths = Array(Set(resolvedPaths))
        guard !paths.isEmpty else { return [:] }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = min(paths.count, ProcessInfo.processInfo.activeProcessorCount)
        let metadataByPath = LockedDictionary<String, ProjectMetadata>(minimumCapacity: paths.count)

        for path in paths {
            queue.addOperation {
                let displayName = URL(fileURLWithPath: path).lastPathComponent
                let gitRoot = Self.metadataCache.gitRoot(for: path) {
                    Self.resolveGitRoot(for: path)
                }
                let commits = gitRoot.map { root in
                    Self.metadataCache.commits(for: root) {
                        Self.loadCommits(in: root)
                    }
                } ?? []

                let metadata = ProjectMetadata(
                    projectKey: gitRoot ?? path,
                    displayName: displayName.isEmpty ? path : displayName,
                    gitRoot: gitRoot,
                    commits: commits
                )
                metadataByPath.set(metadata, for: path)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return metadataByPath.snapshot()
    }

    private func normalizedProjectPath(from rawPath: String) -> String? {
        let expanded = pathResolver.resolve(rawPath)
        var isDirectory: ObjCBool = false
        guard let expanded, fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? expanded : URL(fileURLWithPath: expanded).deletingLastPathComponent().path
    }

    private func normalizedRawProjectPath(_ projectPath: String) -> String {
        projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveGitRoot(for path: String) -> String? {
        guard let result = try? Shell.run(
            arguments: ["git", "-C", path, "rev-parse", "--show-toplevel"],
            timeout: gitProbeTimeout
        ),
              result.status == 0
        else {
            return nil
        }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    private static func loadCommits(in gitRoot: String) -> [GitCommitRecord] {
        guard let result = try? Shell.run(
            arguments: [
                "git", "-C", gitRoot, "log", "--all", "--max-count=250", "--date=iso-strict",
                "--pretty=format:%H%x1f%ad%x1f%s"
            ],
            timeout: gitHistoryTimeout
        ),
        result.status == 0 else {
            return []
        }

        return result.stdout
            .split(separator: "\n")
            .compactMap { line in
                let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 3, let date = DateFormatting.parse(fields[1]) else { return nil }
                return GitCommitRecord(sha: fields[0], date: date, message: fields[2])
            }
            .sorted { $0.date > $1.date }
    }

    private func associatedCommit(for date: Date, in commits: [GitCommitRecord], preferredCommitSHA: String?) -> GitCommitMatch? {
        guard !commits.isEmpty else { return nil }
        let candidates = commits.compactMap { commit -> ScoredCommit? in
            let delta = abs(commit.date.timeIntervalSince(date))
            guard commit.date >= date, delta <= 72 * 60 * 60 else { return nil }

            var score = delta
            if calendar.isDate(commit.date, inSameDayAs: date) {
                score *= 0.55
            }
            if delta <= 2 * 60 * 60 {
                score *= 0.45
            }
            if delta <= 6 * 60 * 60 {
                score *= 0.75
            }
            if matches(commitSHA: preferredCommitSHA, candidateSHA: commit.sha) {
                score *= 0.1
            }

            return ScoredCommit(commit: commit, score: score, delta: delta)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.commit.date > rhs.commit.date
            }
            return lhs.score < rhs.score
        }

        guard let best = candidates.first else { return nil }
        if best.delta <= 30 * 60 {
            return GitCommitMatch(commit: best.commit, confidence: .high)
        }
        if calendar.isDate(best.commit.date, inSameDayAs: date), best.delta <= 6 * 60 * 60 {
            let confidence: CommitConfidence = best.delta <= 2 * 60 * 60 ? .high : .medium
            return GitCommitMatch(commit: best.commit, confidence: confidence)
        }
        if let second = candidates.dropFirst().first, second.score <= best.score * 1.03 {
            return nil
        }
        if best.delta > 18 * 60 * 60 && !calendar.isDate(best.commit.date, inSameDayAs: date) {
            return nil
        }
        let confidence: CommitConfidence = best.delta <= 12 * 60 * 60 ? .medium : .low
        return GitCommitMatch(commit: best.commit, confidence: confidence)
    }

    private func commit(matching sha: String, in commits: [GitCommitRecord]) -> GitCommitRecord? {
        let normalized = sha.lowercased()
        return commits.first { commit in
            let candidate = commit.sha.lowercased()
            return candidate == normalized || candidate.hasPrefix(normalized) || normalized.hasPrefix(candidate)
        }
    }

    private func matches(commitSHA preferred: String?, candidateSHA: String) -> Bool {
        guard let preferred else { return false }
        let normalizedPreferred = preferred.lowercased()
        let normalizedCandidate = candidateSHA.lowercased()
        return normalizedCandidate == normalizedPreferred
            || normalizedCandidate.hasPrefix(normalizedPreferred)
            || normalizedPreferred.hasPrefix(normalizedCandidate)
    }

    private func apply(commit: GitCommitRecord, confidence: CommitConfidence, to prompt: inout ImportedPrompt) {
        prompt.commitSHA = commit.sha
        prompt.commitMessage = commit.message
        prompt.commitDate = commit.date
        prompt.commitConfidence = confidence
        prompt.commitOrphaned = false
    }

    private func clearCommitLink(on prompt: inout ImportedPrompt) {
        prompt.commitSHA = nil
        prompt.commitMessage = nil
        prompt.commitDate = nil
        prompt.commitConfidence = nil
        prompt.commitOrphaned = false
        prompt.commitInsertions = nil
        prompt.commitDeletions = nil
        prompt.commitFilesChanged = nil
    }
}

private struct ProjectMetadata {
    let projectKey: String
    let displayName: String
    let gitRoot: String?
    let commits: [GitCommitRecord]
}

private struct GitCommitRecord {
    let sha: String
    let date: Date
    let message: String
}

private struct GitCommitMatch {
    let commit: GitCommitRecord
    let confidence: CommitConfidence
}

private struct ScoredCommit {
    let commit: GitCommitRecord
    let score: TimeInterval
    let delta: TimeInterval
}

private final class LockedDictionary<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Key: Value]

    init(minimumCapacity: Int = 0) {
        storage = [:]
        storage.reserveCapacity(minimumCapacity)
    }

    func set(_ value: Value, for key: Key) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    func merge<S: Sequence>(_ pairs: S) where S.Element == (Key, Value) {
        lock.lock()
        for (key, value) in pairs {
            storage[key] = value
        }
        lock.unlock()
    }

    func snapshot() -> [Key: Value] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

private final class ProjectMetadataCache: @unchecked Sendable {
    private struct TimedCommits {
        let loadedAt: Date
        let commits: [GitCommitRecord]
    }

    private let queue = DispatchQueue(label: "codebook.imported-prompt-enricher.cache")
    private let commitsTTL: TimeInterval = 30
    private var gitRootsByPath: [String: String?] = [:]
    private var commitsByRoot: [String: TimedCommits] = [:]
    private var diffStatsByKey: [String: GitCommitDiffLookup.Stats] = [:]

    func gitRoot(for path: String, loader: () -> String?) -> String? {
        if let cached = queue.sync(execute: { gitRootsByPath[path] }) {
            return cached
        }

        let resolved = loader()
        queue.sync {
            gitRootsByPath[path] = resolved
        }
        return resolved
    }

    func commits(for gitRoot: String, loader: () -> [GitCommitRecord]) -> [GitCommitRecord] {
        if let cached = queue.sync(execute: { commitsByRoot[gitRoot] }),
           Date().timeIntervalSince(cached.loadedAt) <= commitsTTL {
            return cached.commits
        }

        let commits = loader()
        queue.sync {
            commitsByRoot[gitRoot] = TimedCommits(loadedAt: Date(), commits: commits)
        }
        return commits
    }

    func diffStats(for gitRoot: String, shas: [String]) -> [String: GitCommitDiffLookup.Stats] {
        let normalizedShas = Array(Set(shas.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }))
        guard !normalizedShas.isEmpty else { return [:] }

        let missingShas = queue.sync { () -> [String] in
            normalizedShas.filter { diffStatsByKey[Self.diffKey(gitRoot: gitRoot, sha: $0)] == nil }
        }

        if !missingShas.isEmpty {
            let loaded = GitCommitDiffLookup.statsByCommit(gitRoot: gitRoot, shas: missingShas)
            queue.sync {
                for (sha, stats) in loaded {
                    diffStatsByKey[Self.diffKey(gitRoot: gitRoot, sha: sha)] = stats
                }
            }
        }

        return queue.sync {
            var results: [String: GitCommitDiffLookup.Stats] = [:]
            results.reserveCapacity(normalizedShas.count)
            for sha in normalizedShas {
                if let stats = diffStatsByKey[Self.diffKey(gitRoot: gitRoot, sha: sha)] {
                    results[sha] = stats
                }
            }
            return results
        }
    }

    private static func diffKey(gitRoot: String, sha: String) -> String {
        "\(gitRoot)\u{1e}\(sha)"
    }
}
