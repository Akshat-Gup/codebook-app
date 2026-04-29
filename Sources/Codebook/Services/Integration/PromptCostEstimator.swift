import Foundation

struct PromptCostEstimate: Hashable, Sendable {
    let amountUSD: Double
    let source: Source

    enum Source: String, Hashable, Sendable {
        case measured
    }
}

struct PromptCostSummary: Hashable, Sendable {
    let amountUSD: Double
    let estimatedPromptCount: Int
    let totalPromptCount: Int

    var coverageRatio: Double {
        guard totalPromptCount > 0 else { return 0 }
        return Double(estimatedPromptCount) / Double(totalPromptCount)
    }
}

enum PromptCostEstimator {
    private struct RateCard {
        let inputPerMillionUSD: Double
        let cachedInputPerMillionUSD: Double
        let outputPerMillionUSD: Double
    }

    private struct RateCardEntry {
        let aliases: [String]
        let rateCard: RateCard
    }

    private static let rateCardEntries: [RateCardEntry] = [
        // OpenAI frontier and coding models
        entry(
            aliases: ["gpt-5-4-pro"],
            input: 15.00,
            cachedInput: 3.75,
            output: 120.00
        ),
        entry(
            aliases: ["gpt-5-4", "gpt-5-4-latest"],
            input: 2.00,
            cachedInput: 0.50,
            output: 8.00
        ),
        entry(
            aliases: ["gpt-5-4-mini", "gpt-5-mini"],
            input: 0.75,
            cachedInput: 0.15,
            output: 3.00
        ),
        entry(
            aliases: ["gpt-5-4-nano", "gpt-5-nano"],
            input: 0.20,
            cachedInput: 0.02,
            output: 1.25
        ),
        entry(
            aliases: ["gpt-5-3-codex"],
            input: 1.50,
            cachedInput: 0.375,
            output: 6.00
        ),
        entry(
            aliases: ["gpt-5-codex", "gpt-5-2-codex", "gpt-5-1-codex", "gpt-5-1-codex-max"],
            input: 1.50,
            cachedInput: 0.375,
            output: 6.00
        ),
        entry(
            aliases: ["gpt-5-1-codex-mini", "codex-mini-latest"],
            input: 0.75,
            cachedInput: 0.15,
            output: 3.00
        ),
        entry(
            aliases: ["gpt-5-pro", "gpt-5-2-pro", "o3-pro"],
            input: 15.00,
            cachedInput: 3.75,
            output: 120.00
        ),
        entry(
            aliases: ["gpt-5", "gpt-5-2", "gpt-5-1", "gpt-5-high"],
            input: 2.00,
            cachedInput: 0.50,
            output: 8.00
        ),
        entry(
            aliases: ["gpt-5-3-chat", "gpt-5-3-chat-latest", "gpt-5-3-instant"],
            input: 0.75,
            cachedInput: 0.15,
            output: 3.00
        ),
        entry(
            aliases: ["gpt-5-2-chat", "gpt-5-2-chat-latest", "gpt-5-1-chat", "gpt-5-1-chat-latest", "gpt-5-chat", "gpt-5-chat-latest"],
            input: 2.00,
            cachedInput: 0.50,
            output: 8.00
        ),

        // OpenAI reasoning and GPT-4.x / 4o families
        entry(
            aliases: ["o3", "o3-2025-04-16"],
            input: 2.00,
            cachedInput: 0.50,
            output: 8.00
        ),
        entry(
            aliases: ["o4-mini"],
            input: 1.10,
            cachedInput: 0.275,
            output: 4.40
        ),
        entry(
            aliases: ["o4-mini-deep-research"],
            input: 1.10,
            cachedInput: 0.275,
            output: 4.40
        ),
        entry(
            aliases: ["o3-mini"],
            input: 1.10,
            cachedInput: 0.55,
            output: 4.40
        ),
        entry(
            aliases: ["gpt-4-1"],
            input: 2.00,
            cachedInput: 0.50,
            output: 8.00
        ),
        entry(
            aliases: ["gpt-4-1-mini"],
            input: 0.40,
            cachedInput: 0.10,
            output: 1.60
        ),
        entry(
            aliases: ["gpt-4-1-nano"],
            input: 0.10,
            cachedInput: 0.025,
            output: 0.40
        ),
        entry(
            aliases: ["gpt-4o"],
            input: 2.50,
            cachedInput: 1.25,
            output: 10.00
        ),
        entry(
            aliases: ["gpt-4o-mini", "chatgpt-4o"],
            input: 0.15,
            cachedInput: 0.075,
            output: 0.60
        ),

        // Anthropic Claude families
        entry(
            aliases: ["claude-opus-4-6", "claude-opus-4-5", "claude-4-6-opus-high-thinking", "claude-4-5-opus-high-thinking"],
            input: 5.00,
            cachedInput: 0.50,
            output: 25.00
        ),
        entry(
            aliases: ["claude-opus-4-1", "claude-opus-4", "claude-opus-3"],
            input: 15.00,
            cachedInput: 1.50,
            output: 75.00
        ),
        entry(
            aliases: ["claude-sonnet-4-6", "claude-sonnet-4-5", "claude-sonnet-4", "claude-3-7-sonnet", "claude-4-6-sonnet-medium-thinking", "claude-4-5-sonnet-thinking"],
            input: 3.00,
            cachedInput: 0.30,
            output: 15.00
        ),
        entry(
            aliases: ["claude-3-5-sonnet"],
            input: 3.00,
            cachedInput: 0.30,
            output: 15.00
        ),
        entry(
            aliases: ["claude-haiku-4-5"],
            input: 1.00,
            cachedInput: 0.10,
            output: 5.00
        ),
        entry(
            aliases: ["claude-haiku-3-5"],
            input: 0.80,
            cachedInput: 0.08,
            output: 4.00
        ),
        entry(
            aliases: ["claude-haiku-3"],
            input: 0.25,
            cachedInput: 0.03,
            output: 1.25
        ),

        // Google Gemini API
        entry(
            aliases: ["gemini-2-5-pro"],
            input: 1.25,
            cachedInput: 0.31,
            output: 10.00
        ),
        entry(
            aliases: ["gemini-2-5-flash", "gemini-2-5-flash-image-preview"],
            input: 0.30,
            cachedInput: 0.30,
            output: 2.50
        ),
        entry(
            aliases: ["gemini-2-5-flash-lite"],
            input: 0.10,
            cachedInput: 0.10,
            output: 0.40
        ),
        entry(
            aliases: ["gemini-2-0-flash"],
            input: 0.10,
            cachedInput: 0.10,
            output: 0.40
        ),
        entry(
            aliases: ["gemini-2-0-flash-lite"],
            input: 0.075,
            cachedInput: 0.075,
            output: 0.30
        ),
        entry(
            aliases: ["gemini-1-5-pro"],
            input: 1.25,
            cachedInput: 1.25,
            output: 5.00
        ),
        entry(
            aliases: ["gemini-1-5-flash"],
            input: 0.075,
            cachedInput: 0.075,
            output: 0.30
        ),

        // DeepSeek
        entry(
            aliases: ["deepseek-chat", "deepseek-v3", "deepseek-v3-2"],
            input: 0.28,
            cachedInput: 0.028,
            output: 0.42
        ),
        entry(
            aliases: ["deepseek-reasoner", "deepseek-r1"],
            input: 0.28,
            cachedInput: 0.028,
            output: 0.42
        )
    ]

    static func estimate(for prompt: ImportedPrompt) -> PromptCostEstimate? {
        guard let rateCard = rateCard(for: prompt),
              let inputTokens = prompt.inputTokens ?? prompt.totalTokens,
              let outputTokens = prompt.outputTokens ?? derivedOutputTokens(from: prompt)
        else {
            return nil
        }

        let cachedInputTokens = min(prompt.cachedInputTokens ?? 0, inputTokens)
        let uncachedInputTokens = max(0, inputTokens - cachedInputTokens)
        let amountUSD =
            (Double(uncachedInputTokens) / 1_000_000.0) * rateCard.inputPerMillionUSD +
            (Double(cachedInputTokens) / 1_000_000.0) * rateCard.cachedInputPerMillionUSD +
            (Double(outputTokens) / 1_000_000.0) * rateCard.outputPerMillionUSD

        guard amountUSD.isFinite, amountUSD > 0 else { return nil }
        return PromptCostEstimate(amountUSD: amountUSD, source: .measured)
    }

    static func summarize(_ prompts: [ImportedPrompt]) -> PromptCostSummary {
        let estimates = prompts.compactMap(estimate(for:))
        return PromptCostSummary(
            amountUSD: estimates.reduce(0) { $0 + $1.amountUSD },
            estimatedPromptCount: estimates.count,
            totalPromptCount: prompts.count
        )
    }

    private static func derivedOutputTokens(from prompt: ImportedPrompt) -> Int? {
        guard let totalTokens = prompt.totalTokens,
              let inputTokens = prompt.inputTokens
        else {
            return nil
        }
        return max(0, totalTokens - inputTokens)
    }

    private static func rateCard(for prompt: ImportedPrompt) -> RateCard? {
        let normalizedModel = normalize(prompt.modelID)
        guard !normalizedModel.isEmpty else { return nil }

        return rateCardEntries.first(where: { entry in
            entry.aliases.contains(where: { alias in
                normalizedModel == alias || normalizedModel.hasPrefix(alias + "-")
            })
        })?.rateCard
    }

    private static func entry(
        aliases: [String],
        input: Double,
        cachedInput: Double,
        output: Double
    ) -> RateCardEntry {
        RateCardEntry(
            aliases: aliases.map(normalize),
            rateCard: RateCard(
                inputPerMillionUSD: input,
                cachedInputPerMillionUSD: cachedInput,
                outputPerMillionUSD: output
            )
        )
    }

    private static func normalize(_ rawModelID: String?) -> String {
        guard let rawModelID else { return "" }

        let mappedScalars = rawModelID
            .lowercased()
            .unicodeScalars
            .map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
            }

        let collapsed = String(mappedScalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return collapsed
    }
}
