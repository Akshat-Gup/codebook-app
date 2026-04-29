import Foundation

enum SearchMode: String, CaseIterable, Hashable, Sendable {
    case keyword
    case ai

    var title: String {
        switch self {
        case .keyword: return "Keyword"
        case .ai: return "AI"
        }
    }
}

enum SearchTab: String, CaseIterable, Hashable, Sendable {
    case all
    case commits
    case dates
    case projects
    case tags
    case providers

    var title: String {
        switch self {
        case .all: return "All"
        case .commits: return "Commits"
        case .dates: return "Dates"
        case .projects: return "Projects"
        case .tags: return "Tags"
        case .providers: return "Providers"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .commits: return "arrow.triangle.branch"
        case .dates: return "calendar"
        case .projects: return "folder"
        case .tags: return "tag"
        case .providers: return "cube"
        }
    }
}

enum HistoryGroupingMode: String, CaseIterable, Hashable, Sendable {
    case thread
    case commit

    var title: String {
        switch self {
        case .thread: return "Thread"
        case .commit: return "Commit"
        }
    }
}

enum RepoAutomationExportMode: String, Codable, CaseIterable, Hashable, Sendable {
    case commit // kept for Codable compatibility only; not shown in UI
    case date
    case thread

    static var allCases: [RepoAutomationExportMode] { [.date, .thread] }

    var title: String {
        switch self {
        case .commit: return "By Date"
        case .date: return "By Date"
        case .thread: return "By Thread"
        }
    }

    var systemImage: String {
        switch self {
        case .commit: return "calendar"
        case .date: return "calendar"
        case .thread: return "text.bubble"
        }
    }
}

struct SearchCommitGroup: Identifiable, Hashable, Sendable {
    let key: String
    let message: String
    let sha: String?
    let prompts: [ImportedPrompt]

    var id: String { key }
}

struct SearchDateGroup: Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let date: Date
    let prompts: [ImportedPrompt]

    var id: String { key }
}

struct SearchProjectGroup: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let prompts: [ImportedPrompt]

    var id: String { key }
}

struct SearchTagGroup: Identifiable, Hashable, Sendable {
    let tag: String
    let prompts: [ImportedPrompt]

    var id: String { tag }
}

struct SearchProviderGroup: Identifiable, Hashable, Sendable {
    let provider: IntegrationProvider
    let prompts: [ImportedPrompt]

    var id: IntegrationProvider { provider }
}
