import Foundation

struct PromptTimingSummary: Hashable, Sendable {
    let totalResponseTimeMs: Int
    let measuredPromptCount: Int
    let totalPromptCount: Int

    var coverageRatio: Double {
        guard totalPromptCount > 0 else { return 0 }
        return Double(measuredPromptCount) / Double(totalPromptCount)
    }
}

enum PromptTimingEstimator {
    static func responseTime(for prompt: ImportedPrompt) -> Int? {
        guard let responseTimeMs = prompt.responseTimeMs, responseTimeMs > 0 else { return nil }
        return responseTimeMs
    }

    static func summarize(_ prompts: [ImportedPrompt]) -> PromptTimingSummary {
        let measuredTimes = prompts.compactMap(responseTime(for:))
        return PromptTimingSummary(
            totalResponseTimeMs: measuredTimes.reduce(0, +),
            measuredPromptCount: measuredTimes.count,
            totalPromptCount: prompts.count
        )
    }
}
