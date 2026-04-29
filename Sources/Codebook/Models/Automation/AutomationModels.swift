import Foundation

enum RepoAutomationHookMode: String, Codable, CaseIterable, Hashable, Sendable {
    case prepareCommitMsg
    case postCommit
    case commitMsg

    var title: String {
        switch self {
        case .prepareCommitMsg: return "Prepare Commit Msg"
        case .postCommit: return "Post Commit"
        case .commitMsg: return "Commit Msg"
        }
    }
}

struct RepoAutomationSettings: Codable, Hashable, Sendable {
    var auditEnabled: Bool
    var autoExportEnabled: Bool
    var promptStorePath: String
    var exportMode: RepoAutomationExportMode
    var trackedProviders: [IntegrationProvider]
    var hookMode: RepoAutomationHookMode

    init(
        auditEnabled: Bool = false,
        autoExportEnabled: Bool = true,
        promptStorePath: String = "prompts",
        exportMode: RepoAutomationExportMode = .date,
        trackedProviders: [IntegrationProvider] = Array(IntegrationProvider.allCases).sorted { $0.rawValue < $1.rawValue },
        hookMode: RepoAutomationHookMode = .prepareCommitMsg
    ) {
        self.auditEnabled = auditEnabled
        self.autoExportEnabled = autoExportEnabled
        self.promptStorePath = promptStorePath
        self.exportMode = exportMode
        self.trackedProviders = trackedProviders
        self.hookMode = hookMode
    }

    private enum CodingKeys: String, CodingKey {
        case auditEnabled
        case autoExportEnabled
        case promptStorePath
        case exportMode
        case trackedProviders
        case hookMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            auditEnabled: try container.decodeIfPresent(Bool.self, forKey: .auditEnabled) ?? false,
            autoExportEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoExportEnabled) ?? true,
            promptStorePath: try container.decodeIfPresent(String.self, forKey: .promptStorePath) ?? "prompts",
            exportMode: try container.decodeIfPresent(RepoAutomationExportMode.self, forKey: .exportMode) ?? .date,
            trackedProviders: try container.decodeIfPresent([IntegrationProvider].self, forKey: .trackedProviders)
                ?? Array(IntegrationProvider.allCases).sorted { $0.rawValue < $1.rawValue },
            hookMode: try container.decodeIfPresent(RepoAutomationHookMode.self, forKey: .hookMode) ?? .prepareCommitMsg
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(auditEnabled, forKey: .auditEnabled)
        try container.encode(autoExportEnabled, forKey: .autoExportEnabled)
        try container.encode(promptStorePath, forKey: .promptStorePath)
        try container.encode(exportMode, forKey: .exportMode)
        try container.encode(trackedProviders, forKey: .trackedProviders)
        try container.encode(hookMode, forKey: .hookMode)
    }
}

struct RepoAutomationStatus: Hashable, Sendable {
    let gitRoot: String
    let promptStorePath: String
    let promptStoreExists: Bool
    let promptCount: Int
    let hookInstalled: Bool
    let auditEnabled: Bool
    let autoExportEnabled: Bool
    let trackedProviders: [IntegrationProvider]
    let promptFingerprint: String?
}

struct PromptExportSummary: Hashable, Sendable {
    let gitRoot: String
    let promptStorePath: String
    let exportedFiles: [URL]
    let manifestURL: URL
    let fingerprint: String
    let promptCount: Int
}
