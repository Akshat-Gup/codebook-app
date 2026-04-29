import Foundation

struct GitHubEcosystemSearchResponse: Sendable {
    let results: [GitHubPackageSearchResult]
    let summary: String?
    let usedAIReranking: Bool
}

struct GitHubEcosystemSearchService {
    func search(
        query: String,
        kind: EcosystemPackageKind?,
        mode: EcosystemSearchMode,
        provider: InsightsProvider,
        credentials: ResolvedInsightsCredentials?
    ) async throws -> GitHubEcosystemSearchResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return GitHubEcosystemSearchResponse(results: [], summary: nil, usedAIReranking: false)
        }

        let repos = try await fetchRepositories(query: trimmedQuery, kind: kind)
        let effectiveKind = kind ?? .skill
        guard mode == .ai, let credentials, !repos.isEmpty else {
            return GitHubEcosystemSearchResponse(results: repos, summary: nil, usedAIReranking: false)
        }

        return try await rerankWithAI(
            results: repos,
            query: trimmedQuery,
            kind: effectiveKind,
            provider: provider,
            credentials: credentials
        )
    }

    private func fetchRepositories(query: String, kind: EcosystemPackageKind?) async throws -> [GitHubPackageSearchResult] {
        var components = URLComponents(string: "https://api.github.com/search/repositories")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery(for: query, kind: kind)),
            URLQueryItem(name: "sort", value: "best-match"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "12")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codebook", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CodebookError.network("GitHub search failed.")
        }

        let effectiveKind = kind ?? .skill
        let payload = try JSONDecoder().decode(GitHubRepoSearchPayload.self, from: data)
        return payload.items.map { repo in
            let package = EcosystemPackage(
                id: repo.fullName.lowercased(),
                name: repo.name,
                summary: repo.description ?? "GitHub repository",
                kind: effectiveKind,
                source: .github,
                githubURL: repo.htmlURL,
                defaultContents: "",
                supportedProviders: []
            )
            return GitHubPackageSearchResult(
                id: repo.id,
                name: repo.name,
                fullName: repo.fullName,
                summary: repo.description ?? "GitHub repository",
                url: repo.htmlURL,
                stars: repo.stargazersCount,
                language: repo.language,
                topics: repo.topics,
                kind: effectiveKind,
                sourcePackage: package
            )
        }
    }

    private func rerankWithAI(
        results: [GitHubPackageSearchResult],
        query: String,
        kind: EcosystemPackageKind,
        provider: InsightsProvider,
        credentials: ResolvedInsightsCredentials
    ) async throws -> GitHubEcosystemSearchResponse {
        let system = """
        You rank GitHub repositories for developer tooling discovery.
        Pick the repositories most relevant to the user's request for \(kind.title.lowercased())s.
        Return only JSON:
        {
          "summary": "one short paragraph",
          "ordered_full_names": ["owner/repo", "..."]
        }
        Use only repositories from the provided list.
        """

        let repoList = results.enumerated().map { index, repo in
            """
            \(index + 1). \(repo.fullName)
            Description: \(repo.summary)
            Language: \(repo.language ?? "Unknown")
            Stars: \(repo.stars)
            Topics: \(repo.topics.joined(separator: ", "))
            URL: \(repo.url)
            """
        }.joined(separator: "\n\n")

        let user = """
        Query: \(query)
        Type: \(kind.title)

        Candidates:
        \(repoList)
        """

        let text = try await chat(
            system: system,
            user: user,
            provider: credentials.provider,
            apiKey: credentials.apiKey
        )
        let parsed = parseAIRanking(text: text)
        let ordered = parsed.orderedNames.compactMap { name in
            results.first(where: { $0.fullName.caseInsensitiveCompare(name) == .orderedSame })
        }
        let remainder = results.filter { candidate in
            !ordered.contains(where: { $0.id == candidate.id })
        }
        return GitHubEcosystemSearchResponse(results: ordered + remainder, summary: parsed.summary, usedAIReranking: true)
    }

    private func chat(system: String, user: String, provider: InsightsProvider, apiKey: String) async throws -> String {
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]

        switch provider.protocolStyle {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.apiFeatureModel,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ],
                "temperature": 0.2
            ]
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": provider.defaultModel,
                "max_tokens": 1200,
                "system": system,
                "messages": [["role": "user", "content": user]]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CodebookError.network("AI reranking failed.")
        }
        return AIResponseTextExtractor.extract(from: data, provider: provider)
    }

    private func parseAIRanking(text: String) -> (summary: String?, orderedNames: [String]) {
        let jsonString = EmbeddedJSONExtractor.extractObjectText(from: text)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, [])
        }
        return (
            summary: json["summary"] as? String,
            orderedNames: json["ordered_full_names"] as? [String] ?? []
        )
    }

    private func searchQuery(for query: String, kind: EcosystemPackageKind?) -> String {
        guard let kind else {
            return "\(query) in:name,description,readme"
        }
        let qualifier: String
        switch kind {
        case .skill:
            qualifier = "topic:ai-skill OR topic:cursor-rules OR topic:agents-md"
        case .plugin:
            qualifier = "topic:ai-plugin OR topic:agent-plugin"
        case .mcp:
            qualifier = "topic:mcp OR topic:mcp-server"
        case .app:
            qualifier = "topic:ai-agent OR topic:agent-tool"
        }
        return "\(query) \(qualifier) in:name,description,readme"
    }
}

private struct GitHubRepoSearchPayload: Decodable {
    let items: [GitHubRepoPayload]
}

private struct GitHubRepoPayload: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let htmlURL: String
    let stargazersCount: Int
    let language: String?
    let topics: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case description
        case htmlURL = "html_url"
        case stargazersCount = "stargazers_count"
        case language
        case topics
    }
}
