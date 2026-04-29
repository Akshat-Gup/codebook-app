import CryptoKit
import Foundation

enum IntegrationProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claude
    case cursor
    case copilot
    case opencode
    case antigravity

    var title: String {
        switch self {
        case .codex, .claude, .cursor, .copilot:
            return rawValue.capitalized
        case .opencode:
            return "OpenCode"
        case .antigravity:
            return "Antigravity"
        }
    }
}

struct ImportedPrompt: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let provider: IntegrationProvider
    let title: String
    let body: String
    let sourcePath: String
    let projectPath: String?
    let capturedAt: Date
    let metadataOnly: Bool
    var projectName: String
    var projectKey: String
    var gitRoot: String?
    var commitSHA: String?
    var commitMessage: String?
    var commitDate: Date?
    var commitConfidence: CommitConfidence?
    var tags: [String]
    var commitOrphaned: Bool
    var sourceContextID: String?
    var modelID: String?
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var responseTimeMs: Int?
    /// Aggregate line stats for the linked git commit (`git show --shortstat`). Shared when multiple prompts map to one commit.
    var commitInsertions: Int?
    var commitDeletions: Int?
    var commitFilesChanged: Int?
    private let stableLibraryKeyStorage: String
    private let legacyLibraryKeyStorage: String

    init(
        id: String,
        provider: IntegrationProvider,
        title: String,
        body: String,
        sourcePath: String,
        projectPath: String?,
        capturedAt: Date,
        metadataOnly: Bool,
        projectName: String? = nil,
        projectKey: String? = nil,
        gitRoot: String? = nil,
        commitSHA: String? = nil,
        commitMessage: String? = nil,
        commitDate: Date? = nil,
        commitConfidence: CommitConfidence? = nil,
        tags: [String] = [],
        commitOrphaned: Bool = false,
        sourceContextID: String? = nil,
        modelID: String? = nil,
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        responseTimeMs: Int? = nil,
        commitInsertions: Int? = nil,
        commitDeletions: Int? = nil,
        commitFilesChanged: Int? = nil
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.body = body
        self.sourcePath = sourcePath
        self.projectPath = projectPath
        self.capturedAt = capturedAt
        self.metadataOnly = metadataOnly
        self.projectName = projectName ?? (projectPath.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? provider.title)
        self.projectKey = projectKey ?? (projectPath ?? "provider:\(provider.rawValue)")
        self.gitRoot = gitRoot
        self.commitSHA = commitSHA
        self.commitMessage = commitMessage
        self.commitDate = commitDate
        self.commitConfidence = commitConfidence
        self.tags = tags
        self.commitOrphaned = commitOrphaned
        self.sourceContextID = sourceContextID
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.responseTimeMs = responseTimeMs
        self.commitInsertions = commitInsertions
        self.commitDeletions = commitDeletions
        self.commitFilesChanged = commitFilesChanged
        self.stableLibraryKeyStorage = Self.makeStableLibraryKey(
            provider: provider,
            projectKey: self.projectKey,
            sourceContextID: sourceContextID,
            sourcePath: sourcePath,
            capturedAt: capturedAt,
            title: title,
            body: body
        )
        self.legacyLibraryKeyStorage = Self.makeLegacyLibraryKey(
            provider: provider,
            projectKey: self.projectKey,
            sourceContextID: sourceContextID,
            sourcePath: sourcePath,
            capturedAt: capturedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case title
        case body
        case sourcePath
        case projectPath
        case capturedAt
        case metadataOnly
        case projectName
        case projectKey
        case gitRoot
        case commitSHA
        case commitMessage
        case commitDate
        case commitConfidence
        case tags
        case commitOrphaned
        case sourceContextID
        case modelID
        case inputTokens
        case cachedInputTokens
        case outputTokens
        case totalTokens
        case responseTimeMs
        case commitInsertions
        case commitDeletions
        case commitFilesChanged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            provider: container.decode(IntegrationProvider.self, forKey: .provider),
            title: container.decode(String.self, forKey: .title),
            body: container.decode(String.self, forKey: .body),
            sourcePath: container.decode(String.self, forKey: .sourcePath),
            projectPath: container.decodeIfPresent(String.self, forKey: .projectPath),
            capturedAt: container.decode(Date.self, forKey: .capturedAt),
            metadataOnly: container.decode(Bool.self, forKey: .metadataOnly),
            projectName: container.decodeIfPresent(String.self, forKey: .projectName),
            projectKey: container.decodeIfPresent(String.self, forKey: .projectKey),
            gitRoot: container.decodeIfPresent(String.self, forKey: .gitRoot),
            commitSHA: container.decodeIfPresent(String.self, forKey: .commitSHA),
            commitMessage: container.decodeIfPresent(String.self, forKey: .commitMessage),
            commitDate: container.decodeIfPresent(Date.self, forKey: .commitDate),
            commitConfidence: container.decodeIfPresent(CommitConfidence.self, forKey: .commitConfidence),
            tags: container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            commitOrphaned: container.decodeIfPresent(Bool.self, forKey: .commitOrphaned) ?? false,
            sourceContextID: container.decodeIfPresent(String.self, forKey: .sourceContextID),
            modelID: container.decodeIfPresent(String.self, forKey: .modelID),
            inputTokens: container.decodeIfPresent(Int.self, forKey: .inputTokens),
            cachedInputTokens: container.decodeIfPresent(Int.self, forKey: .cachedInputTokens),
            outputTokens: container.decodeIfPresent(Int.self, forKey: .outputTokens),
            totalTokens: container.decodeIfPresent(Int.self, forKey: .totalTokens),
            responseTimeMs: container.decodeIfPresent(Int.self, forKey: .responseTimeMs),
            commitInsertions: container.decodeIfPresent(Int.self, forKey: .commitInsertions),
            commitDeletions: container.decodeIfPresent(Int.self, forKey: .commitDeletions),
            commitFilesChanged: container.decodeIfPresent(Int.self, forKey: .commitFilesChanged)
        )
    }

    /// When `projectPath` is nil, `projectKey` is `provider:<rawValue>` (not a repo path). Those keys must not appear as sidebar folders.
    static let syntheticProviderProjectKeyPrefix = "provider:"

    /// Stable across history rescans while remaining prompt-specific inside a thread.
    var stableLibraryKey: String {
        stableLibraryKeyStorage
    }

    /// Pre-1.0.18 key format. Thread-scoped when `sourceContextID` is present.
    var legacyLibraryKey: String {
        legacyLibraryKeyStorage
    }

    static func usesLegacyLibraryKeyFormat(_ key: String) -> Bool {
        !key.hasPrefix("prompt:")
    }

    var effectiveDate: Date {
        commitDate ?? capturedAt
    }

    var hasMeasuredUsage: Bool {
        inputTokens != nil || outputTokens != nil || totalTokens != nil
    }

    var hasMeasuredResponseTime: Bool {
        (responseTimeMs ?? 0) > 0
    }

    var hasCommitLineStats: Bool {
        (commitInsertions ?? 0) > 0 || (commitDeletions ?? 0) > 0 || (commitFilesChanged ?? 0) > 0
    }

    /// Naive “both touched” estimate for share cards (not a true changed-line count).
    var commitLinesChangedEstimate: Int {
        min(commitInsertions ?? 0, commitDeletions ?? 0)
    }

    /// Sidebar / group secondary label: short SHA with optional `+ins −del` (commit-wide totals).
    var commitSubtitleLabel: String? {
        guard let sha = commitSHA else { return nil }
        let short = String(sha.prefix(7))
        let ins = max(0, commitInsertions ?? 0)
        let del = max(0, commitDeletions ?? 0)
        if ins > 0 || del > 0 {
            return "\(short)  +\(ins) −\(del)"
        }
        if let files = commitFilesChanged, files > 0 {
            return "\(short)  \(files) files"
        }
        return short
    }

    /// Tags suitable for list/detail UI: omits entries redundant with `projectName` and `provider`
    /// (for example `PromptTagger` stores `provider.rawValue`, which duplicates `provider.title`).
    var displayTags: [String] {
        tags.filter { tag in
            let t = tag.lowercased()
            return t != provider.title.lowercased() &&
                t != Slug.make(from: provider.title) &&
                t != provider.rawValue.lowercased() &&
                t != projectName.lowercased() &&
                t != Slug.make(from: projectName)
        }
    }

    private var normalizedSourceContextID: String? {
        let trimmed = sourceContextID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var stableCapturedAtToken: String {
        String(format: "%.6f", capturedAt.timeIntervalSince1970)
    }

    private static func makeStableLibraryKey(
        provider: IntegrationProvider,
        projectKey: String,
        sourceContextID: String?,
        sourcePath: String,
        capturedAt: Date,
        title: String,
        body: String
    ) -> String {
        let payload = [
            provider.rawValue,
            projectKey,
            normalizeSourceContextID(sourceContextID) ?? "",
            sourcePath,
            stableCapturedAtToken(for: capturedAt),
            title,
            body
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "prompt:\(digest.hexString)"
    }

    private static func makeLegacyLibraryKey(
        provider: IntegrationProvider,
        projectKey: String,
        sourceContextID: String?,
        sourcePath: String,
        capturedAt: Date
    ) -> String {
        if let scid = normalizeSourceContextID(sourceContextID) {
            return "scid:\(provider.rawValue):\(projectKey):\(scid)"
        }
        return "file:\(provider.rawValue):\(sourcePath):\(stableCapturedAtToken(for: capturedAt))"
    }

    private static func normalizeSourceContextID(_ sourceContextID: String?) -> String? {
        let trimmed = sourceContextID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func stableCapturedAtToken(for capturedAt: Date) -> String {
        String(format: "%.6f", capturedAt.timeIntervalSince1970)
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

enum CommitConfidence: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: return "Strong"
        case .medium: return "Likely"
        case .low: return "Weak"
        }
    }
}

struct ProjectSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String?
    let promptCount: Int
    let isManual: Bool
}

enum PromptGroupKind: Hashable, Sendable {
    case single
    case thread
    case commit
}

struct PromptGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let prompts: [ImportedPrompt]
    let date: Date
    let structured: Bool
    let kind: PromptGroupKind
}

struct DayPromptGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let date: Date
    let groups: [PromptGroup]
}

enum PromptThreading {
    static func key(for prompt: ImportedPrompt) -> String {
        let contextID = prompt.sourceContextID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContextID = contextID?.isEmpty == false ? contextID : nil
        if let normalizedContextID {
            return "\(prompt.provider.rawValue)|\(prompt.projectKey)|context|\(normalizedContextID)"
        }
        return "\(prompt.provider.rawValue)|\(prompt.projectKey)|path|\(prompt.sourcePath)"
    }

    static func commitDiffKey(for prompt: ImportedPrompt) -> String? {
        guard prompt.hasCommitLineStats else { return nil }
        let files = max(0, prompt.commitFilesChanged ?? 0)
        let ins = max(0, prompt.commitInsertions ?? 0)
        let del = max(0, prompt.commitDeletions ?? 0)
        return "stats|\(files)|\(ins)|\(del)"
    }

    static func latestCommitDiffPromptIDs(in prompts: [ImportedPrompt]) -> Set<String> {
        var selectedIDs = Set<String>()
        var currentRunKey: String?
        var currentRunPromptID: String?

        for prompt in prompts {
            let diffKey = commitDiffKey(for: prompt)
            if diffKey == currentRunKey {
                continue
            }

            if let currentRunPromptID {
                selectedIDs.insert(currentRunPromptID)
            }

            currentRunKey = diffKey
            currentRunPromptID = diffKey == nil ? nil : prompt.id
        }

        if let currentRunPromptID {
            selectedIDs.insert(currentRunPromptID)
        }

        return selectedIDs
    }

    static func latestPromptIDs(in prompts: [ImportedPrompt]) -> Set<String> {
        let grouped = Dictionary(grouping: prompts, by: key(for:))
        return Set(grouped.values.compactMap { prompts in
            prompts.max { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.id < rhs.id
                }
                return lhs.capturedAt < rhs.capturedAt
            }?.id
        })
    }
}

/// Defines what to batch-send.
