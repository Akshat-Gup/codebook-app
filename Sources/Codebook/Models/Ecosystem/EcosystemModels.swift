import Foundation

enum EcosystemPackageKind: String, Codable, CaseIterable, Hashable, Sendable {
    case skill
    case plugin
    case mcp
    case app

    var title: String {
        switch self {
        case .skill: return "Skill"
        case .plugin: return "Plugin"
        case .mcp: return "MCP"
        case .app: return "App"
        }
    }

    var systemImage: String {
        switch self {
        case .skill: return "wand.and.stars"
        case .plugin: return "shippingbox"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .app: return "app.connected.to.app.below.fill"
        }
    }
}

enum EcosystemPackageSource: String, Codable, Hashable, Sendable {
    case bundled
    case github
    case local

    var title: String {
        switch self {
        case .bundled: return "Bundled"
        case .github: return "GitHub"
        case .local: return "Local"
        }
    }
}

struct EcosystemPackage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let kind: EcosystemPackageKind
    let source: EcosystemPackageSource
    let githubURL: String?
    let defaultContents: String
    let supportedProviders: [String]

    init(
        id: String,
        name: String,
        summary: String,
        kind: EcosystemPackageKind,
        source: EcosystemPackageSource,
        githubURL: String? = nil,
        defaultContents: String,
        supportedProviders: [String]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.kind = kind
        self.source = source
        self.githubURL = githubURL
        self.defaultContents = defaultContents
        self.supportedProviders = supportedProviders
    }
}

struct ProviderInstallDestination: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let rootPath: String
    let skillsPath: String
    let pluginsPath: String
    let mcpPath: String
    let appsPath: String
    let isBuiltIn: Bool

    func path(for kind: EcosystemPackageKind) -> String {
        switch kind {
        case .skill: return skillsPath
        case .plugin: return pluginsPath
        case .mcp: return mcpPath
        case .app: return appsPath
        }
    }

    var integrationProvider: IntegrationProvider? {
        IntegrationProvider(rawValue: id)
    }
}

struct ProviderInstallSnapshot: Identifiable, Hashable, Sendable {
    let target: ProviderInstallDestination
    let skillCount: Int
    let pluginCount: Int
    let mcpCount: Int
    let appCount: Int
    let existingKinds: Set<EcosystemPackageKind>

    var id: String { target.id }
}

struct CustomProviderProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var rootPath: String
    var skillsFolder: String
    var pluginsFolder: String
    var mcpFolder: String
    var appsFolder: String

    init(
        id: String = UUID().uuidString,
        name: String,
        rootPath: String,
        skillsFolder: String = "skills",
        pluginsFolder: String = "plugins",
        mcpFolder: String = "mcp",
        appsFolder: String = "apps"
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.skillsFolder = skillsFolder
        self.pluginsFolder = pluginsFolder
        self.mcpFolder = mcpFolder
        self.appsFolder = appsFolder
    }
}

enum EcosystemSearchMode: String, CaseIterable, Hashable, Sendable {
    case keyword
    case ai

    var title: String {
        switch self {
        case .keyword: return "Search"
        case .ai: return "AI Search"
        }
    }
}

struct GitHubPackageSearchResult: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let summary: String
    let url: String
    let stars: Int
    let language: String?
    let topics: [String]
    let kind: EcosystemPackageKind
    let sourcePackage: EcosystemPackage
}

enum AgentsAdvicePack: String, Codable, CaseIterable, Hashable, Sendable {
    case openai
    case anthropic
    case codex
    case claudeCode
    case cursor
    case copilot

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        case .copilot: return "GitHub Copilot"
        }
    }

    var body: String {
        switch self {
        case .openai:
            return """
            - Prefer explicit success criteria, file paths, and verification steps.
            - Ask for up-to-date facts only when they affect correctness.
            - Keep requests scoped so the agent can finish in one pass.
            """
        case .anthropic:
            return """
            - State the desired reasoning depth and any constraints on tool use.
            - Separate immutable rules from task-specific preferences.
            - Encourage concise plans before large edits.
            """
        case .codex:
            return """
            - Mention whether the agent should code immediately or pause for a plan.
            - Call out required verification commands and review expectations.
            - Be explicit about files the agent should or should not touch.
            """
        case .claudeCode:
            return """
            - Include repo-specific guardrails close to the top of the file.
            - Spell out how much explanation you want versus direct action.
            - Note any preferred shell commands or sandbox expectations.
            """
        case .cursor:
            return """
            - Keep implementation patterns concrete so inline edits stay consistent.
            - Document preferred component, naming, and refactor conventions.
            - Mention whether generated code should prioritize speed or polish.
            """
        case .copilot:
            return """
            - Keep comments and examples short so suggestions remain high signal.
            - Document project patterns the model should copy by default.
            - List common pitfalls the assistant should avoid repeating.
            """
        }
    }
}

struct AgentsProjectAudit: Identifiable, Hashable, Sendable {
    let projectID: String
    let projectName: String
    let projectPath: String
    let agentsFilePath: String
    let claudeFilePath: String
    let fileExists: Bool
    let claudeFileExists: Bool
    let managedByCodebook: Bool
    let hasSharedBase: Bool
    let includedAdvice: Set<AgentsAdvicePack>
    let missingAdvice: [AgentsAdvicePack]
    let filesAreSynchronized: Bool
    let syncDetailText: String
    let statusText: String
    let detailText: String

    var id: String { projectID }
}
