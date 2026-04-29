import Foundation

struct AgentsTemplateService {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func defaultSharedBase() -> String {
        """
        # Shared operating rules

        - Match the surrounding codebase before introducing new patterns.
        - Prefer concise clarifying questions when a decision changes scope or risk.
        - Verify meaningful changes with the smallest command that proves the result.
        - Keep communication direct, calm, and specific.
        """
    }

    func auditProjects(
        _ projects: [ProjectSummary],
        sharedBase: String,
        selectedAdvice: Set<AgentsAdvicePack>
    ) -> [AgentsProjectAudit] {
        projects.compactMap { project in
            guard let path = project.path else { return nil }
            let agentsURL = URL(fileURLWithPath: path).appendingPathComponent("AGENTS.md")
            let claudeURL = URL(fileURLWithPath: path).appendingPathComponent("CLAUDE.md")
            let filePath = agentsURL.path
            let claudeFilePath = claudeURL.path
            let fileExists = fileManager.fileExists(atPath: filePath)
            let claudeFileExists = fileManager.fileExists(atPath: claudeFilePath)
            let content = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""
            let managed = content.contains("Managed by Codebook")
            let hasShared = content.contains(sharedBase.trimmingCharacters(in: .whitespacesAndNewlines))
                || content.contains("# Shared operating rules")
            let includedAdvice = Set(selectedAdvice.filter { content.contains($0.title) })
            let missingAdvice = selectedAdvice.subtracting(includedAdvice).sorted { $0.title < $1.title }
            let filesAreSynchronized = fileExists
                && claudeFileExists
                && normalizedInstructionBody(content) == normalizedInstructionBody((try? String(contentsOf: claudeURL, encoding: .utf8)) ?? "")
            let syncDetailText: String
            switch (fileExists, claudeFileExists, filesAreSynchronized) {
            case (false, false, _):
                syncDetailText = "Neither AGENTS.md nor CLAUDE.md exists yet."
            case (false, true, _), (true, false, _):
                syncDetailText = "One instruction file is missing."
            case (true, true, true):
                syncDetailText = "AGENTS.md and CLAUDE.md are synchronized."
            case (true, true, false):
                syncDetailText = "AGENTS.md and CLAUDE.md contain different guidance."
            }

            let statusText: String
            let detailText: String
            if !fileExists {
                statusText = "Missing"
                detailText = "No AGENTS.md yet."
            } else if !managed {
                statusText = "Unmanaged"
                detailText = missingAdvice.isEmpty ? "Existing file can be merged into the shared format." : "\(missingAdvice.count) advice pack(s) missing."
            } else if !hasShared || !missingAdvice.isEmpty {
                statusText = "Needs update"
                detailText = !hasShared ? "Shared baseline is missing." : "\(missingAdvice.count) advice pack(s) missing."
            } else {
                statusText = "Aligned"
                detailText = "Shared baseline and selected advice are present."
            }

            return AgentsProjectAudit(
                projectID: project.id,
                projectName: project.name,
                projectPath: path,
                agentsFilePath: filePath,
                claudeFilePath: claudeFilePath,
                fileExists: fileExists,
                claudeFileExists: claudeFileExists,
                managedByCodebook: managed,
                hasSharedBase: hasShared,
                includedAdvice: includedAdvice,
                missingAdvice: missingAdvice,
                filesAreSynchronized: filesAreSynchronized,
                syncDetailText: syncDetailText,
                statusText: statusText,
                detailText: detailText
            )
        }
        .sorted { lhs, rhs in
            if lhs.statusText == rhs.statusText {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            return lhs.statusText.localizedCaseInsensitiveCompare(rhs.statusText) == .orderedAscending
        }
    }

    func preview(
        fileName: String = "AGENTS.md",
        projectName: String,
        sharedBase: String,
        selectedAdvice: Set<AgentsAdvicePack>,
        existingContent: String?
    ) -> String {
        let trimmedBase = sharedBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedAdvice = selectedAdvice.sorted { $0.title < $1.title }
        let preserved = existingProjectOverrides(from: existingContent)

        var lines: [String] = [
            "# \(fileName)",
            "",
            "<!-- Managed by Codebook -->",
            "",
            trimmedBase,
            "",
            "# Provider advice",
            ""
        ]

        if sortedAdvice.isEmpty {
            lines.append("- No provider advice selected yet.")
            lines.append("")
        } else {
            for pack in sortedAdvice {
                lines.append("## \(pack.title)")
                lines.append("")
                lines.append(pack.body)
                lines.append("")
            }
        }

        lines.append("# Project overrides")
        lines.append("")
        if preserved.isEmpty {
            lines.append("- Repo: \(projectName)")
            lines.append("- Add local conventions, verification commands, or architecture notes here.")
        } else {
            lines.append(preserved)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    @discardableResult
    func applyTemplate(
        to projectPath: String,
        projectName: String,
        sharedBase: String,
        selectedAdvice: Set<AgentsAdvicePack>
    ) throws -> URL {
        let agentsURL = URL(fileURLWithPath: projectPath).appendingPathComponent("AGENTS.md")
        let existing = try? String(contentsOf: agentsURL, encoding: .utf8)
        let rendered = preview(
            projectName: projectName,
            sharedBase: sharedBase,
            selectedAdvice: selectedAdvice,
            existingContent: existing
        )
        try backupIfNeeded(existingContent: existing, renderedContent: rendered, at: agentsURL)
        try SecureFileStore.write(Data(rendered.utf8), to: agentsURL)
        return agentsURL
    }

    @discardableResult
    func synchronizeInstructionFiles(
        in projectPath: String,
        projectName: String,
        sharedBase: String,
        selectedAdvice: Set<AgentsAdvicePack>
    ) throws -> [URL] {
        let agentsURL = URL(fileURLWithPath: projectPath).appendingPathComponent("AGENTS.md")
        let claudeURL = URL(fileURLWithPath: projectPath).appendingPathComponent("CLAUDE.md")
        let agentsExisting = try? String(contentsOf: agentsURL, encoding: .utf8)
        let claudeExisting = try? String(contentsOf: claudeURL, encoding: .utf8)
        let fallback = preview(
            projectName: projectName,
            sharedBase: sharedBase,
            selectedAdvice: selectedAdvice,
            existingContent: agentsExisting ?? claudeExisting
        )
        let mergedBody = mergedInstructionBody(
            primary: agentsExisting ?? fallback,
            secondary: claudeExisting ?? fallback
        )
        let renderedAgents = renderedInstructionFile(named: "AGENTS.md", body: mergedBody)
        let renderedClaude = renderedInstructionFile(named: "CLAUDE.md", body: mergedBody)

        try backupIfNeeded(existingContent: agentsExisting, renderedContent: renderedAgents, at: agentsURL)
        try backupIfNeeded(existingContent: claudeExisting, renderedContent: renderedClaude, at: claudeURL)
        try SecureFileStore.write(Data(renderedAgents.utf8), to: agentsURL)
        try SecureFileStore.write(Data(renderedClaude.utf8), to: claudeURL)
        return [agentsURL, claudeURL]
    }

    private func existingProjectOverrides(from content: String?) -> String {
        guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            return ""
        }
        if let range = content.range(of: "# Project overrides") {
            let suffix = content[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix
        }
        return content
    }

    func normalizedInstructionBody(_ content: String) -> String {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var bodyLines = lines
        while let first = bodyLines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyLines.removeFirst()
        }

        if let first = bodyLines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           first == "# AGENTS.md" || first == "# CLAUDE.md" {
            bodyLines.removeFirst()
        }

        while let first = bodyLines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyLines.removeFirst()
        }
        while let last = bodyLines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyLines.removeLast()
        }

        var normalized: [String] = []
        for line in bodyLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !normalized.isEmpty, normalized.last != "" {
                    normalized.append("")
                }
            } else {
                normalized.append(trimmed)
            }
        }

        return normalized.joined(separator: "\n")
    }

    func mergedInstructionBody(primary: String, secondary: String) -> String {
        let primaryLines = normalizedInstructionBody(primary)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let secondaryLines = normalizedInstructionBody(secondary)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var merged: [String] = []
        var seen = Set<String>()

        func append(_ lines: [String]) {
            for line in lines {
                if line.isEmpty {
                    if !merged.isEmpty, merged.last != "" {
                        merged.append("")
                    }
                    continue
                }

                if seen.insert(line).inserted {
                    merged.append(line)
                }
            }
        }

        append(primaryLines)
        append(secondaryLines)

        while let last = merged.last, last.isEmpty {
            merged.removeLast()
        }

        return merged.joined(separator: "\n")
    }

    func renderedInstructionFile(named fileName: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "# \(fileName)\n" }
        return "# \(fileName)\n\n\(trimmed)\n"
    }

    private func backupIfNeeded(existingContent: String?, renderedContent: String, at url: URL) throws {
        guard let existingContent,
              !existingContent.isEmpty,
              existingContent != renderedContent else { return }

        let backupName = url.deletingPathExtension().lastPathComponent + ".codebook.backup.md"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)
        try SecureFileStore.write(Data(existingContent.utf8), to: backupURL)
    }
}
