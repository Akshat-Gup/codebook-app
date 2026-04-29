import Foundation

/// Scans a project's codebase and generates an architectural SVG diagram via AI.
struct DiagramGenerator {

    /// Maximum total characters of source context sent to the model.
    private static let contextCharacterBudget = 12_000

    /// Directories that should never appear in the scan.
    private static let ignoredDirectories: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "DerivedData",
        "Pods", "Carthage", ".swiftpm", "__pycache__", ".next", ".nuxt",
        "dist", "build", "vendor", ".venv", "venv", ".tox", "target",
        ".gradle", ".idea", ".vs", ".vscode", "xcuserdata"
    ]

    /// File extensions considered interesting for architecture context.
    private static let interestingExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt",
        "rb", "ex", "exs", "cs", "cpp", "c", "h", "hpp", "m", "mm",
        "proto", "graphql", "sql"
    ]

    /// Sentinel files read in full (up to a cap) because they carry project-wide info.
    private static let sentinelFiles: Set<String> = [
        "Package.swift", "Cargo.toml", "go.mod", "pyproject.toml",
        "package.json", "build.gradle", "pom.xml", "Gemfile",
        "CMakeLists.txt", "Makefile", "docker-compose.yml", "Dockerfile",
        "README.md", "README.rst", "AGENTS.md", "CLAUDE.md"
    ]

    // MARK: - Codebase Scanning

    /// Build a textual context string that describes the project structure and key files.
    func scanCodebase(at path: String) throws -> String {
        let rootURL = URL(fileURLWithPath: path)
        let fm = FileManager.default

        var tree: [String] = []
        var sentinelContents: [(name: String, body: String)] = []

        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            if Self.ignoredDirectories.contains(name) {
                enumerator?.skipDescendants()
                continue
            }

            let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                tree.append("📁 \(relativePath)/")
            } else {
                tree.append("   \(relativePath)")
                if Self.sentinelFiles.contains(name) {
                    if let data = fm.contents(atPath: url.path),
                       let text = String(data: data, encoding: .utf8) {
                        sentinelContents.append((name: relativePath, body: String(text.prefix(2000))))
                    }
                }
            }
        }

        var context = "# Project: \(rootURL.lastPathComponent)\n\n"
        context += "## Directory tree\n```\n"
        context += tree.prefix(500).joined(separator: "\n")
        if tree.count > 500 { context += "\n... (\(tree.count - 500) more entries)" }
        context += "\n```\n\n"

        for sentinel in sentinelContents {
            context += "## \(sentinel.name)\n```\n\(sentinel.body)\n```\n\n"
        }

        return String(context.prefix(Self.contextCharacterBudget))
    }

    // MARK: - Prompt Construction

    /// System + user prompt for generating a diagram of the given kind.
    func diagramPrompt(for kind: DiagramKind, context: String) -> (system: String, user: String) {
        let system = """
        You are a senior software architect. Given a project's directory structure and key configuration files, \
        produce a complete, self-contained SVG diagram that visualizes the software architecture.

        RULES:
        1. Return ONLY valid SVG markup (no markdown fences, no explanation outside the SVG).
        2. The SVG must start with `<svg` and end with `</svg>`.
        3. Use a clean, modern style with rounded rectangles, clear labels, and directional arrows.
        4. Group related components visually.
        5. Show data-flow arrows between layers where relevant.
        6. Use a light background (#f8f9fa) and professional color palette.
        7. Make the SVG viewBox large enough to be readable (at least 900×600).
        8. Include a title element inside the SVG with the project name.
        9. Keep text legible: minimum 12px font size.
        """

        let focus: String
        switch kind {
        case .overview:
            focus = "Generate a comprehensive architectural overview showing all major components, layers, and their relationships."
        case .components:
            focus = "Generate a diagram focused on the main components and modules, their responsibilities, and how they relate to each other."
        case .dataFlow:
            focus = "Generate a data flow diagram showing how data moves through the system — inputs, transformations, storage, and outputs."
        case .dependencies:
            focus = "Generate a dependencies diagram showing external libraries, frameworks, and services the project depends on, and which internal modules use them."
        case .entryPoints:
            focus = "Generate a diagram showing the entry points of the application (main executables, CLI commands, API endpoints, event handlers) and how they wire into the rest of the system."
        case .patterns:
            focus = "Generate a diagram illustrating the design patterns used in this codebase (MVC, MVVM, Repository, Observer, etc.) and where they appear."
        case .layers:
            focus = "Generate a layered architecture diagram showing the distinct layers (e.g. Presentation, Business Logic, Data Access, Infrastructure) and the boundaries between them."
        case .feature(let name):
            focus = "Generate a focused diagram for the '\(name)' feature: show only the files, components, and data flows directly relevant to that feature."
        }

        let user = """
        Analyze this codebase and generate an SVG diagram.

        Focus: \(focus)

        \(context)
        """

        return (system, user)
    }

    func questionPrompt(
        question: String,
        currentSVG: String?,
        codebaseContext: String
    ) -> (system: String, user: String) {
        let system = """
        You answer follow-up questions about a software architecture diagram.

        RULES:
        1. If the user is asking to change or refine the diagram, return ONLY complete valid SVG markup.
        2. If the user is asking for explanation, answer in concise plain text.
        3. Never return markdown fences.
        4. When returning SVG, preserve the overall structure when possible and apply only the requested change.
        """

        var userSections: [String] = [
            "Question: \(question)"
        ]
        if !codebaseContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userSections.append("Codebase context:\n\(codebaseContext)")
        }
        if let currentSVG, !currentSVG.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userSections.append("Current SVG:\n\(String(currentSVG.prefix(12_000)))")
        }

        return (system, userSections.joined(separator: "\n\n"))
    }

    // MARK: - Response Parsing

    /// Extract the SVG content from an AI response string.
    func extractSVG(from text: String) -> String? {
        guard let svgStart = text.range(of: "<svg", options: .caseInsensitive),
              let svgEnd = text.range(of: "</svg>", options: [.caseInsensitive, .backwards])
        else {
            return nil
        }
        return String(text[svgStart.lowerBound..<svgEnd.upperBound])
    }

    func responseContainsSVG(_ text: String) -> Bool {
        extractSVG(from: text) != nil
    }
}
