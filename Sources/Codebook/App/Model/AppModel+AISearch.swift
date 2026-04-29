import Foundation

extension AppModel {

    func handleSearchChange() {
        searchDebounceTask?.cancel()

        guard !searchInputText.isEmpty else {
            applySearchText("")
            return
        }

        let pendingSearchText = searchInputText
        let debounceDuration = searchDebounceDuration
        searchDebounceTask = Task.detached { [weak self, pendingSearchText, debounceDuration] in
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            await self?.applySearchText(pendingSearchText)
        }

    }

    func setSearchMode(_ mode: SearchMode) {
        guard searchMode != mode else { return }
        searchMode = mode
        aiSearchResults = []
        aiSearchQuery = nil
        aiSearchError = nil
        aiSearchReasoning = nil
        aiSearchSummary = nil
        aiSearchTask?.cancel()
        aiSearchIsRunning = false
    
    }

    func runAISearch() {
        scheduleAISearch()
    }

    func scheduleAISearch() {
        aiSearchTask?.cancel()
        aiSearchIsRunning = false
        aiSearchError = nil
        aiSearchReasoning = nil
        aiSearchSummary = nil

        guard !searchInputText.isEmpty else {
            aiSearchResults = []
            aiSearchQuery = nil
            return
        }

        aiSearchQuery = searchInputText

        loadInsightsApiKeyIfNeeded()
        guard insightsAIAvailable else {
            aiSearchResults = []
            return
        }

        let query = searchInputText
        let prompts = importedPrompts.filter(isPromptVisibleInLibrary)
        let provider = selectedInsightsProvider

        aiSearchIsRunning = true
        aiSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.performAISearch(
                    query: query,
                    prompts: prompts,
                    provider: provider
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.aiSearchResults = result.prompts
                    self.aiSearchReasoning = result.reasoning ?? self.aiSearchReasoning
                    self.aiSearchSummary = result.summary
                    self.aiSearchIsRunning = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.aiSearchError = error.localizedDescription
                    self.aiSearchIsRunning = false
                }
            }
        }
    }

    struct AISearchResult {
        let prompts: [ImportedPrompt]
        let reasoning: String?
        let summary: String?
    }

    func performAISearch(query: String, prompts: [ImportedPrompt], provider: InsightsProvider) async throws -> AISearchResult {
        appendAISearchTrace("Starting AI search for \"\(query)\"")
        appendAISearchTrace("Running tool-based search.")
        return try await performAgenticSearch(
            query: query,
            prompts: prompts,
            provider: provider
        )
    }

    func performAgenticSearch(query: String, prompts: [ImportedPrompt], provider: InsightsProvider) async throws -> AISearchResult {
        let insightsProvider = provider
        let promptMap = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0) })

        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "search_prompts",
                    "description": "Search through the user's prompt history using keyword matching. Returns matching prompts with their IDs, titles, providers, tags, and a body preview. Use multiple searches with different keywords to find relevant prompts.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Search keywords (space-separated, matched against title, body, tags, project, provider, commit message)"
                            ],
                            "limit": [
                                "type": "integer",
                                "description": "Max results to return (default 20, max 50)"
                            ]
                        ],
                        "required": ["query"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_prompt",
                    "description": "Get the full details of a specific prompt by its ID, including the complete body text.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "id": [
                                "type": "string",
                                "description": "The prompt ID to retrieve"
                            ]
                        ],
                        "required": ["id"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_projects",
                    "description": "List all projects in the prompt database with their prompt counts.",
                    "parameters": [
                        "type": "object",
                        "properties": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_tags",
                    "description": "List all unique tags used across prompts.",
                    "parameters": [
                        "type": "object",
                        "properties": [:] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]

        let system = """
        You are an AI search agent for a developer's prompt history (their "codebook"). You have tools to search and explore their entire prompt database.

        Use the tools to find prompts relevant to the user's query. You can search multiple times with different keywords to be thorough.

        When you have found enough relevant prompts, respond with a JSON object in this exact format:
        {
            "reasoning": "Brief explanation of your search process and what you found",
            "summary": "A concise paragraph summarizing the relevant prompts and how they relate to the query",
            "ids": ["id1", "id2", ...]
        }

        Return at most 20 IDs, ordered by relevance. If nothing is relevant, return empty ids.
        Return ONLY the JSON object in your final response, no other text.
        """
        let userMessage = "Search query: \(query)\n\nTotal prompts in database: \(prompts.count)"

        var messages: [[String: Any]] = [
            ["role": "user", "content": userMessage]
        ]

        let maxIterations = 10
        for _ in 0..<maxIterations {
            try Task.checkCancellation()

            let responseData = try await callLLMWithTools(
                messages: messages,
                system: system,
                tools: tools,
                provider: insightsProvider
            )

            let (text, toolCalls, stopReason) = parseToolCallResponse(from: responseData, provider: insightsProvider)

            if let traceText = condensedAISearchTrace(from: text) {
                appendAISearchTrace(traceText)
            }

            if toolCalls.isEmpty || stopReason == "end_turn" || stopReason == "stop" {
                let finalText = text ?? ""
                return parseAISearchResult(from: finalText, promptMap: promptMap)
            }

            messages.append(buildAssistantMessage(text: text, toolCalls: toolCalls, provider: insightsProvider))

            for call in toolCalls {
                appendAISearchTrace(descriptionForAISearchToolCall(call))
                let result = executeLocalTool(name: call.name, arguments: call.arguments, prompts: prompts)
                if let toolSummary = summaryForAISearchToolResult(named: call.name, result: result) {
                    appendAISearchTrace(toolSummary)
                }
                messages.append(buildToolResultMessage(callID: call.id, result: result, provider: insightsProvider))
            }
        }

        return AISearchResult(prompts: [], reasoning: "Search reached maximum iterations.", summary: nil)
    }

    struct ToolCall {
        let id: String
        let name: String
        let arguments: [String: Any]
    }

    func callPlainLLM(system: String, userMessage: String, provider: InsightsProvider) async throws -> Data {
        let credentials = try resolveInsightsCredentials(for: provider)
        let transportProvider = credentials.provider
        var request = URLRequest(url: transportProvider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any]
        switch transportProvider.protocolStyle {
        case .openAICompatible:
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": transportProvider.apiFeatureModel,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userMessage]
                ],
                "temperature": 0
            ]

        case .anthropicMessages:
            request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": transportProvider.defaultModel,
                "max_tokens": 2048,
                "system": system,
                "messages": [["role": "user", "content": userMessage]]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw CodebookError.network("AI search synthesis failed. \(responseBody.prefix(200))")
        }

        return data
    }

    func callLLMWithTools(messages: [[String: Any]], system: String, tools: [[String: Any]], provider: InsightsProvider) async throws -> Data {
        let credentials = try resolveInsightsCredentials(for: provider)
        let transportProvider = credentials.provider
        var request = URLRequest(url: transportProvider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        switch transportProvider.protocolStyle {
        case .openAICompatible:
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": transportProvider.apiFeatureModel,
                "messages": [["role": "system", "content": system]] + messages,
                "tools": tools,
                "temperature": 0
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropicMessages:
            request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let anthropicTools = tools.compactMap { tool -> [String: Any]? in
                guard let fn = tool["function"] as? [String: Any] else { return nil }
                return [
                    "name": fn["name"] as? String ?? "",
                    "description": fn["description"] as? String ?? "",
                    "input_schema": fn["parameters"] as? [String: Any] ?? [:]
                ]
            }
            let body: [String: Any] = [
                "model": transportProvider.defaultModel,
                "max_tokens": 4096,
                "system": system,
                "messages": messages,
                "tools": anthropicTools
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CodebookError.network("AI search request failed. \(body.prefix(200))")
        }
        return data
    }

    func parseToolCallResponse(from data: Data, provider: InsightsProvider) -> (text: String?, toolCalls: [ToolCall], stopReason: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, [], nil)
        }

        switch provider.protocolStyle {
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any] else { return (nil, [], nil) }

            let text = message["content"] as? String
            let finishReason = first["finish_reason"] as? String
            var calls: [ToolCall] = []

            if let toolCallsArr = message["tool_calls"] as? [[String: Any]] {
                for tc in toolCallsArr {
                    guard let id = tc["id"] as? String,
                          let fn = tc["function"] as? [String: Any],
                          let name = fn["name"] as? String,
                          let argsStr = fn["arguments"] as? String,
                          let argsData = argsStr.data(using: .utf8),
                          let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else { continue }
                    calls.append(ToolCall(id: id, name: name, arguments: args))
                }
            }

            let stopReason = (finishReason == "stop" && calls.isEmpty) ? "stop" : nil
            return (text, calls, stopReason)

        case .anthropicMessages:
            let stopReason = json["stop_reason"] as? String
            guard let content = json["content"] as? [[String: Any]] else { return (nil, [], stopReason) }

            var text: String?
            var calls: [ToolCall] = []

            for block in content {
                let type = block["type"] as? String
                if type == "text" {
                    text = block["text"] as? String
                } else if type == "tool_use" {
                    guard let id = block["id"] as? String,
                          let name = block["name"] as? String,
                          let input = block["input"] as? [String: Any] else { continue }
                    calls.append(ToolCall(id: id, name: name, arguments: input))
                }
            }

            return (text, calls, calls.isEmpty ? "end_turn" : stopReason)
        }
    }

    func buildAssistantMessage(text: String?, toolCalls: [ToolCall], provider: InsightsProvider) -> [String: Any] {
        switch provider.protocolStyle {
        case .openAICompatible:
            var msg: [String: Any] = ["role": "assistant"]
            if let text { msg["content"] = text }
            let tcArr: [[String: Any]] = toolCalls.map { call in
                let argsData = (try? JSONSerialization.data(withJSONObject: call.arguments)) ?? Data()
                return [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": String(data: argsData, encoding: .utf8) ?? "{}"
                    ]
                ]
            }
            msg["tool_calls"] = tcArr
            return msg

        case .anthropicMessages:
            var content: [[String: Any]] = []
            if let text { content.append(["type": "text", "text": text]) }
            for call in toolCalls {
                content.append([
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": call.arguments
                ])
            }
            return ["role": "assistant", "content": content]
        }
    }

    func buildToolResultMessage(callID: String, result: String, provider: InsightsProvider) -> [String: Any] {
        switch provider.protocolStyle {
        case .openAICompatible:
            return [
                "role": "tool",
                "tool_call_id": callID,
                "content": result
            ]
        case .anthropicMessages:
            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": callID,
                        "content": result
                    ]
                ]
            ]
        }
    }

    func appendAISearchTrace(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = aiSearchReasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            guard !existing.contains(trimmed) else { return }
            aiSearchReasoning = existing + "\n\n" + trimmed
        } else {
            aiSearchReasoning = trimmed
        }
    }

    func condensedAISearchTrace(from text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let line = trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let line else { return nil }
        return line
    }

    func descriptionForAISearchToolCall(_ call: ToolCall) -> String {
        switch call.name {
        case "search_prompts":
            let query = (call.arguments["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return query.isEmpty ? "Searching prompt history." : "Searching prompt history for \"\(query)\""
        case "get_prompt":
            let id = (call.arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? "Inspecting a prompt in full." : "Inspecting prompt \(id)."
        case "list_projects":
            return "Reviewing project groups."
        case "list_tags":
            return "Reviewing tags across prompt history."
        default:
            return "Running \(call.name)."
        }
    }

    func summaryForAISearchToolResult(named name: String, result: String) -> String? {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        switch name {
        case "search_prompts":
            if let items = json as? [[String: Any]] {
                return "Found \(items.count) candidate prompts."
            }
        case "list_projects":
            if let items = json as? [[String: Any]] {
                return "Scanned \(items.count) projects."
            }
        case "list_tags":
            if let items = json as? [[String: Any]] {
                return "Scanned \(items.count) tags."
            }
        case "get_prompt":
            if let item = json as? [String: Any],
               let title = item["title"] as? String,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Loaded prompt details for \"\(title)\""
            }
            return "Loaded full prompt details."
        default:
            break
        }

        return nil
    }

    func executeLocalTool(name: String, arguments: [String: Any], prompts: [ImportedPrompt]) -> String {
        switch name {
        case "search_prompts":
            guard let query = arguments["query"] as? String else { return "[]" }
            let limit = min(arguments["limit"] as? Int ?? 20, 50)
            let tokens = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return "[]" }

            let scored = prompts.compactMap { prompt -> (ImportedPrompt, Double)? in
                guard let cache = promptSearchCaches[prompt.id] else { return nil }
                let score = searchScore(for: cache, tokens: tokens)
                return score > 0 ? (prompt, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

            let results = scored.map { (prompt, _) -> [String: String] in
                [
                    "id": prompt.id,
                    "title": prompt.title,
                    "provider": prompt.provider.title,
                    "project": prompt.projectName,
                    "tags": prompt.tags.joined(separator: ", "),
                    "date": ISO8601DateFormatter().string(from: prompt.capturedAt),
                    "body_preview": String(prompt.body.prefix(200)),
                    "commit": prompt.commitMessage ?? ""
                ]
            }
            let data = (try? JSONSerialization.data(withJSONObject: Array(results))) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"

        case "get_prompt":
            guard let id = arguments["id"] as? String,
                  let prompt = prompts.first(where: { $0.id == id }) else { return "{\"error\": \"Prompt not found\"}" }
            let result: [String: String] = [
                "id": prompt.id,
                "title": prompt.title,
                "provider": prompt.provider.title,
                "project": prompt.projectName,
                "tags": prompt.tags.joined(separator: ", "),
                "date": ISO8601DateFormatter().string(from: prompt.capturedAt),
                "body": String(prompt.body.prefix(2000)),
                "commit_sha": prompt.commitSHA ?? "",
                "commit_message": prompt.commitMessage ?? ""
            ]
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"

        case "list_projects":
            var counts: [String: Int] = [:]
            for p in prompts { counts[p.projectName, default: 0] += 1 }
            let sorted = counts.sorted { $0.value > $1.value }
            let results = sorted.map { ["project": $0.key, "count": "\($0.value)"] }
            let data = (try? JSONSerialization.data(withJSONObject: results)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"

        case "list_tags":
            var tagCounts: [String: Int] = [:]
            for p in prompts { for t in p.tags { tagCounts[t, default: 0] += 1 } }
            let sorted = tagCounts.sorted { $0.value > $1.value }.prefix(50)
            let results = sorted.map { ["tag": $0.key, "count": "\($0.value)"] }
            let data = (try? JSONSerialization.data(withJSONObject: results)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"

        default:
            return "{\"error\": \"Unknown tool\"}"
        }
    }

    func parseAISearchResult(from text: String, promptMap: [String: ImportedPrompt]) -> AISearchResult {
        let jsonString = EmbeddedJSONExtractor.extractObjectText(from: text)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AISearchResult(prompts: [], reasoning: nil, summary: nil)
        }

        let ids = (json["ids"] as? [String]) ?? []
        let reasoning = json["reasoning"] as? String
        let summary = json["summary"] as? String
        let matched = ids.compactMap { promptMap[$0] }

        return AISearchResult(prompts: matched, reasoning: reasoning, summary: summary)
    }

    func extractAIText(from data: Data, provider: InsightsProvider) -> String {
        AIResponseTextExtractor.extract(from: data, provider: provider)
    }

    func parseAISearchIDs(from text: String) -> [String] {
        let jsonString = EmbeddedJSONExtractor.extractObjectText(from: text)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = json["ids"] as? [String] else { return [] }
        return ids
    }

}
