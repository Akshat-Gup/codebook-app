import Foundation

enum PromptTagger {
    private static let keywords = [
        "analyze", "brainstorm", "code", "debug", "design", "docs", "explain",
        "fix", "plan", "prompt", "refactor", "review", "search", "ship",
        "summarize", "test", "translate", "write"
    ]

    static func tags(for prompt: ImportedPrompt, projectName: String) -> [String] {
        let haystack = [prompt.title, prompt.body].joined(separator: " ").lowercased()
        var tags = Set<String>()
        tags.insert(prompt.provider.rawValue)
        if prompt.metadataOnly {
            tags.insert("metadata")
        }

        let projectTag = Slug.make(from: projectName)
        if !projectTag.isEmpty {
            tags.insert(projectTag)
        }

        for keyword in keywords where haystack.contains(keyword) {
            tags.insert(keyword)
        }

        return Array(tags).sorted()
    }
}
