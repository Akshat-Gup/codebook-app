import Foundation

struct InsightsAnalyzer {

    func analyzeLocalChanges(workspacePath: String, credentials: ResolvedInsightsCredentials) async throws -> InsightsResult {
        let insightsProvider = credentials.provider
        let userContent = try localChangesContext(workspacePath: workspacePath)

        let systemPrompt = """
        You are an expert code reviewer and AI prompt engineer.
        Given the git diff of a developer's local changes, suggest targeted prompting strategies for getting better AI assistance on this work.
        Return ONLY valid JSON with exactly this structure:
        {
          "better_prompts": [
            {"title": "...", "detail": "...", "example": "..."}
          ],
          "strategies": [
            {"title": "...", "detail": "...", "example": "..."}
          ],
          "skills": [
            {"title": "...", "detail": "...", "example": "..."}
          ]
        }
        - better_prompts: Up to 5 prompts or rewrites that would help with these changes. In "example", write the actual prompt text.
        - strategies: Up to 5 development strategies based on the observed changes. In "example", a one-liner on applying it.
        - skills: Up to 5 automation or reusable skill ideas for this type of work.
        Titles ≤ 8 words. Details ≤ 2 sentences. Example ≤ 1 sentence.
        """

        let responseText = try await chat(provider: insightsProvider, apiKey: credentials.apiKey, system: systemPrompt, user: userContent)
        return try parseResponseOrThrow(responseText)
    }

    func analyze(prompts: [ImportedPrompt], credentials: ResolvedInsightsCredentials) async throws -> InsightsResult {
        let insightsProvider = credentials.provider
        let systemPrompt = buildSystemPrompt()
        let userContent = buildUserContent(from: prompts)
        let responseText = try await chat(
            provider: insightsProvider,
            apiKey: credentials.apiKey,
            system: systemPrompt,
            user: userContent
        )
        return try parseResponseOrThrow(responseText)
    }

    // MARK: - Private

    func localChangesContext(workspacePath: String) throws -> String {
        let repositoryName = URL(fileURLWithPath: workspacePath).lastPathComponent
        let isRepository = try git(arguments: ["-C", workspacePath, "rev-parse", "--is-inside-work-tree"])
        guard isRepository.status == 0,
              isRepository.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw CodebookError.invalidRepository(repositoryName)
        }

        let statusResult = try git(arguments: ["-C", workspacePath, "status", "--short", "--untracked-files=all"])
        guard statusResult.status == 0 else {
            throw CodebookError.invalidRepository(repositoryName)
        }

        let status = statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let unpushedCount = GitLocalWorkProbe.unpushedCommitCount(gitRoot: workspacePath)
        guard !status.isEmpty || unpushedCount > 0 else {
            throw CodebookError.noLocalChanges(repositoryName)
        }

        let hasHead = (try git(arguments: ["-C", workspacePath, "rev-parse", "--verify", "HEAD"])).status == 0
        if !status.isEmpty {
            let diff = try localChangesDiff(workspacePath: workspacePath, hasHead: hasHead)
            if diff.isEmpty {
                return "Git status:\n\(status)\n\nGit diff:\nNo textual diff available. Focus on the status entries, especially untracked files."
            }

            return "Git status:\n\(status)\n\nGit diff (truncated):\n\(diff)"
        }

        let summary = try git(arguments: ["-C", workspacePath, "status", "-sb"])
        let summaryLine = summary.stdout.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let diff = try upstreamDiff(workspacePath: workspacePath)
        if diff.isEmpty {
            return """
            Git status:
            \(summaryLine)
            \(unpushedCount) local commit(s) not on upstream yet (clean worktree).

            Git diff:
            No textual diff available versus upstream.
            """
        }

        return """
        Git status:
        \(summaryLine)
        \(unpushedCount) local commit(s) not on upstream yet (clean worktree).

        Git diff vs upstream (truncated):
        \(diff)
        """
    }

    private func buildSystemPrompt() -> String {
        """
        You are an expert AI prompt engineer and software productivity analyst.
        Analyze the provided prompt history from a developer's AI tools (Codex, Claude, Cursor, Copilot).
        Return ONLY valid JSON with exactly this structure:
        {
          "better_prompts": [
            {"title": "...", "detail": "...", "example": "..."}
          ],
          "strategies": [
            {"title": "...", "detail": "...", "example": "..."}
          ],
          "skills": [
            {"title": "...", "detail": "...", "example": "..."}
          ]
        }
        - better_prompts: Up to 5 specific improvements. In "example", cite a real excerpt or short rewrite of one of the user's actual prompts.
        - strategies: Up to 5 repo-level strategies. In "example", show a concrete one-liner of how to apply it.
        - skills: Up to 5 recurring patterns that could be turned into reusable skills or automations. In "example", sketch the prompt template.
        Be concise. Titles ≤ 8 words. Details ≤ 2 sentences. Example ≤ 1 sentence.
        """
    }

    func buildUserContent(from prompts: [ImportedPrompt]) -> String {
        let sortedPrompts = prompts.sorted { $0.capturedAt > $1.capturedAt }
        let recentPrompts = Array(sortedPrompts.prefix(40))
        guard let newestPrompt = recentPrompts.first,
              let oldestPrompt = recentPrompts.last else {
            return "No imported prompt history is available."
        }

        let excerptLength = promptExcerptLength(for: recentPrompts)
        let promptLines = recentPrompts.map { promptLine(for: $0, excerptLength: excerptLength) }

        return """
        Analyze patterns across my recent imported prompt history.

        Recent prompts analyzed: \(recentPrompts.count)
        Total imported prompts available: \(sortedPrompts.count)
        Date range: \(timestampString(for: oldestPrompt.capturedAt)) -> \(timestampString(for: newestPrompt.capturedAt))
        Providers: \(topCounts(recentPrompts.map(\.provider.title), limit: 6))
        Projects: \(topCounts(recentPrompts.map(\.projectName), limit: 8))
        Tags: \(topCounts(recentPrompts.flatMap(\.tags), limit: 10))

        Recent prompt timeline (newest first):
        \(promptLines.joined(separator: "\n"))
        """
    }

    private func localChangesDiff(workspacePath: String, hasHead: Bool) throws -> String {
        let baseArguments = [
            "-C", workspacePath,
            "diff",
            "--no-ext-diff",
            "--no-color",
            "--submodule=short",
            "--stat",
            "--summary",
            "--unified=1"
        ]

        var sections: [String] = []
        if hasHead {
            let diffResult = try git(arguments: baseArguments + ["HEAD"])
            if diffResult.status == 0 {
                sections.append(diffResult.stdout)
            }
        } else {
            let stagedResult = try git(arguments: baseArguments + ["--cached"])
            if stagedResult.status == 0 {
                let staged = stagedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !staged.isEmpty {
                    sections.append("Staged changes:\n\(staged)")
                }
            }

            let unstagedResult = try git(arguments: baseArguments)
            if unstagedResult.status == 0 {
                let unstaged = unstagedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !unstaged.isEmpty {
                    sections.append("Unstaged changes:\n\(unstaged)")
                }
            }
        }

        let joined = sections
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(joined.prefix(3000))
    }

    private func upstreamDiff(workspacePath: String) throws -> String {
        let upstreamCheck = try git(arguments: ["-C", workspacePath, "rev-parse", "--verify", "@{upstream}"])
        guard upstreamCheck.status == 0 else { return "" }

        let diffResult = try git(arguments: [
            "-C", workspacePath,
            "diff",
            "--no-ext-diff",
            "--no-color",
            "--submodule=short",
            "--stat",
            "--summary",
            "--unified=1",
            "@{upstream}..HEAD"
        ])
        guard diffResult.status == 0 else { return "" }
        return String(diffResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
    }

    private func git(arguments: [String]) throws -> ShellResult {
        try Shell.run("/usr/bin/git", arguments: arguments)
    }

    private func chat(provider: InsightsProvider, apiKey: String, system: String, user: String) async throws -> String {
        var request = URLRequest(url: provider.baseURL)
        switch provider.protocolStyle {
        case .openAICompatible:
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": provider.apiFeatureModel,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ],
                "temperature": 0
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropicMessages:
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": provider.defaultModel,
                "max_tokens": 1024,
                "system": system,
                "messages": [
                    ["role": "user", "content": user]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CodebookError.network("Insights API request failed. \(body.prefix(120))")
        }

        return AIResponseTextExtractor.extract(from: data, provider: provider)
    }

    func parseResponse(_ text: String) -> InsightsResult {
        let jsonString = extractJSONObjectString(from: text) ?? text

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return InsightsResult(betterPrompts: [], strategies: [], skills: [], analyzedAt: .now)
        }

        func parseItems(_ key: String) -> [InsightItem] {
            guard let arr = json[key] as? [[String: Any]] else { return [] }
            return arr.compactMap { item in
                guard let title = item["title"] as? String,
                      let detail = item["detail"] as? String else { return nil }
                let example = item["example"] as? String
                return InsightItem(id: UUID().uuidString, title: title, detail: detail, example: example)
            }
        }

        return InsightsResult(
            betterPrompts: parseItems("better_prompts"),
            strategies: parseItems("strategies"),
            skills: parseItems("skills"),
            analyzedAt: .now
        )
    }

    private func parseResponseOrThrow(_ text: String) throws -> InsightsResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CodebookError.network("Insights returned an empty response.")
        }

        let result = parseResponse(trimmed)
        guard !(result.betterPrompts.isEmpty && result.strategies.isEmpty && result.skills.isEmpty) else {
            throw CodebookError.network("Insights returned no suggestions.")
        }
        return result
    }

    private func promptExcerptLength(for prompts: [ImportedPrompt]) -> Int {
        let metadataBudget = prompts.reduce(into: 0) { partialResult, prompt in
            partialResult += prompt.title.count
            partialResult += prompt.provider.title.count
            partialResult += prompt.projectName.count
            partialResult += 32
        }

        let remainingBudget = max(0, 120_000 - metadataBudget)
        return min(120, remainingBudget / max(prompts.count, 1))
    }

    private func promptLine(for prompt: ImportedPrompt, excerptLength: Int) -> String {
        let prefix: String
        if excerptLength > 0 {
            let compactBody = prompt.body
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            prefix = compactBody.isEmpty ? "" : " | " + String(compactBody.prefix(excerptLength))
        } else {
            prefix = ""
        }

        return "- \(timestampString(for: prompt.capturedAt)) | \(prompt.provider.title) | \(prompt.projectName) | \(prompt.title)\(prefix)"
    }

    private func topCounts(_ values: [String], limit: Int) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "None" }

        let counts = Dictionary(cleaned.map { ($0, 1) }, uniquingKeysWith: +)
        let sorted = counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }

        let top = sorted.prefix(limit).map { "\($0.key) (\($0.value))" }
        let remainingCount = max(0, sorted.count - limit)
        if remainingCount > 0 {
            return top.joined(separator: ", ") + ", +\(remainingCount) more"
        }
        return top.joined(separator: ", ")
    }

    private func timestampString(for date: Date) -> String {
        date.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .time(includingFractionalSeconds: false)
        )
    }

    private func extractJSONObjectString(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaping = false

        for index in text[start...].indices {
            let character = text[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                    continue
                }
                if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                depth += 1
                continue
            }

            if character == "}" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
