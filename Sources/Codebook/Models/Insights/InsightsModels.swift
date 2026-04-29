import Foundation

struct InsightsResult: Sendable {
    let betterPrompts: [InsightItem]
    let strategies: [InsightItem]
    let skills: [InsightItem]
    let analyzedAt: Date
}

struct InsightItem: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let example: String?
}

enum InsightsProviderProtocol: Sendable {
    case openAICompatible
    case anthropicMessages
}

/// Provider choices for the Insights AI feature.
enum InsightsProvider: String, CaseIterable, Hashable, Sendable {
    case openai
    case anthropic
    case gemini
    case xai
    case groq
    case mistral
    case cohere
    case together
    case openrouter
    case deepseek
    case fireworks

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI"
        case .groq: return "Groq"
        case .mistral: return "Mistral"
        case .cohere: return "Cohere"
        case .together: return "Together AI"
        case .openrouter: return "OpenRouter"
        case .deepseek: return "DeepSeek"
        case .fireworks: return "Fireworks AI"
        }
    }

    var protocolStyle: InsightsProviderProtocol {
        switch self {
        case .anthropic:
            return .anthropicMessages
        case .openai, .gemini, .xai, .groq, .mistral, .cohere, .together, .openrouter, .deepseek, .fireworks:
            return .openAICompatible
        }
    }

    var baseURL: URL {
        switch self {
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .xai: return URL(string: "https://api.x.ai/v1/chat/completions")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")!
        case .cohere: return URL(string: "https://api.cohere.ai/compatibility/v1/chat/completions")!
        case .together: return URL(string: "https://api.together.xyz/v1/chat/completions")!
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .deepseek: return URL(string: "https://api.deepseek.com/v1/chat/completions")!
        case .fireworks: return URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5.4-mini"
        case .anthropic: return "claude-haiku-4-5"
        case .gemini: return "gemini-2.5-flash"
        case .xai: return "grok-code-fast-1"
        case .groq: return "openai/gpt-oss-20b"
        case .mistral: return "devstral-small-latest"
        case .cohere: return "command-a-03-2025"
        case .together: return "openai/gpt-oss-20b"
        case .openrouter: return "openai/gpt-oss-20b"
        case .deepseek: return "deepseek-chat"
        case .fireworks: return "accounts/fireworks/models/llama-v3p1-8b-instruct"
        }
    }

    var apiFeatureModel: String {
        switch self {
        case .openai: return "gpt-5.4-nano"
        case .anthropic: return defaultModel
        case .gemini: return "gemini-2.5-flash"
        case .xai: return "grok-code-fast-1"
        case .groq: return "openai/gpt-oss-20b"
        case .mistral: return "devstral-small-latest"
        case .cohere: return "command-a-03-2025"
        case .together: return "openai/gpt-oss-20b"
        case .openrouter: return "openai/gpt-oss-20b"
        case .deepseek: return "deepseek-chat"
        case .fireworks: return "accounts/fireworks/models/llama-v3p1-8b-instruct"
        }
    }

    var diagramModel: String {
        switch self {
        case .openai: return "gpt-5.4-mini"
        case .anthropic: return "claude-haiku-4-5"
        case .gemini: return "gemini-2.5-flash"
        case .xai: return "grok-code-fast-1"
        case .groq: return "openai/gpt-oss-20b"
        case .mistral: return "devstral-small-latest"
        case .cohere: return "command-a-03-2025"
        case .together: return "openai/gpt-oss-20b"
        case .openrouter: return "openai/gpt-oss-20b"
        case .deepseek: return "deepseek-chat"
        case .fireworks: return "accounts/fireworks/models/llama-v3p1-8b-instruct"
        }
    }

    var isOpenAICompatible: Bool { protocolStyle == .openAICompatible }

    var keychainAccount: String {
        "insights-api-key-\(rawValue)"
    }

    var legacyKeychainAccounts: [String] {
        switch self {
        case .openai:
            return ["openai-api-key"]
        default:
            return []
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        default: return "Paste API key"
        }
    }

    var menuSystemImage: String {
        switch self {
        case .openai: return "bubble.left.and.bubble.right.fill"
        case .anthropic: return "sparkles"
        case .gemini: return "diamond.fill"
        case .xai: return "xmark"
        case .groq: return "bolt.fill"
        case .mistral: return "wind"
        case .cohere: return "triangle.fill"
        case .together: return "square.stack.3d.up.fill"
        case .openrouter: return "rotate.3d"
        case .deepseek: return "brain.head.profile"
        case .fireworks: return "fireworks"
        }
    }
}

struct ResolvedInsightsCredentials: Sendable {
    let provider: InsightsProvider
    let apiKey: String
}
