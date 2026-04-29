import Foundation

struct EcosystemWorkspaceService {
    private struct PluginManifest: Decodable {
        struct Interface: Decodable {
            let displayName: String?
            let shortDescription: String?
            let longDescription: String?
        }

        let name: String?
        let description: String?
        let interface: Interface?
    }

    let fileManager: FileManager
    let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func bundledCatalog() -> [EcosystemPackage] {
        let providerIDs = builtInTargets().map(\.id)
        return [
            EcosystemPackage(
                id: "frontend-design",
                name: "frontend-design",
                summary: "UI direction, typography, and polish rules for product-facing work.",
                kind: .skill,
                source: .bundled,
                defaultContents: """
                # Frontend Design

                Focus on clarity, restrained motion, and visual hierarchy. Match existing product patterns before introducing new chrome.
                """,
                supportedProviders: providerIDs
            ),
            EcosystemPackage(
                id: "playwright-smoke",
                name: "playwright-smoke",
                summary: "Short browser checks, snapshots, and failure triage helpers.",
                kind: .skill,
                source: .bundled,
                defaultContents: """
                # Playwright Smoke

                Use small, deterministic browser checks. Capture console errors, the visible state, and one screenshot before reporting failures.
                """,
                supportedProviders: providerIDs
            ),
            EcosystemPackage(
                id: "provider-toolkit",
                name: "provider-toolkit",
                summary: "Workspace plugin shell for syncing shared skills, MCPs, and provider metadata.",
                kind: .plugin,
                source: .bundled,
                defaultContents: """
                {
                  "name": "provider-toolkit",
                  "displayName": "Provider Toolkit",
                  "description": "Codebook-managed package for shared agent setup."
                }
                """,
                supportedProviders: providerIDs
            ),
            EcosystemPackage(
                id: "figma-bridge",
                name: "figma-bridge",
                summary: "Starter MCP server manifest for design handoff workflows.",
                kind: .mcp,
                source: .bundled,
                defaultContents: """
                {
                  "name": "figma-bridge",
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-figma"],
                  "transport": "stdio"
                }
                """,
                supportedProviders: providerIDs
            ),
            EcosystemPackage(
                id: "workspace-companion",
                name: "workspace-companion",
                summary: "Small app manifest for repo-aware helper tools and workspace actions.",
                kind: .app,
                source: .bundled,
                defaultContents: """
                {
                  "name": "workspace-companion",
                  "entrypoint": "./index.js",
                  "description": "Repo-aware helper app for Codebook"
                }
                """,
                supportedProviders: providerIDs
            )
        ]
    }

    func installTargets(customProviders: [CustomProviderProfile]) -> [ProviderInstallDestination] {
        builtInTargets() + customProviders.map { profile in
            ProviderInstallDestination(
                id: profile.id,
                name: profile.name,
                systemImage: "tray.full",
                rootPath: expandPath(profile.rootPath),
                skillsPath: expandPath(profile.rootPath + "/" + profile.skillsFolder),
                pluginsPath: expandPath(profile.rootPath + "/" + profile.pluginsFolder),
                mcpPath: expandPath(profile.rootPath + "/" + profile.mcpFolder),
                appsPath: expandPath(profile.rootPath + "/" + profile.appsFolder),
                isBuiltIn: false
            )
        }
    }

    func snapshot(for target: ProviderInstallDestination) -> ProviderInstallSnapshot {
        let skillCount = countEntries(at: target.skillsPath)
        let pluginCount = countEntries(at: target.pluginsPath, kind: .plugin)
        let mcpCount = countEntries(at: target.mcpPath)
        let appCount = countEntries(at: target.appsPath)
        var kinds = Set<EcosystemPackageKind>()
        if skillCount > 0 { kinds.insert(.skill) }
        if pluginCount > 0 { kinds.insert(.plugin) }
        if mcpCount > 0 { kinds.insert(.mcp) }
        if appCount > 0 { kinds.insert(.app) }
        return ProviderInstallSnapshot(
            target: target,
            skillCount: skillCount,
            pluginCount: pluginCount,
            mcpCount: mcpCount,
            appCount: appCount,
            existingKinds: kinds
        )
    }

    func isInstalled(_ package: EcosystemPackage, on target: ProviderInstallDestination) -> Bool {
        if package.kind == .plugin {
            return !installedPluginRoots(matching: package, on: target).isEmpty
        }
        return fileManager.fileExists(atPath: packageURL(for: package, target: target).path)
    }

    /// Packages present on disk under any install target but not necessarily listed in the bundled catalog
    /// (for example GitHub installs, manual folders, or custom skills).
    func discoverInstalledPackages(targets: [ProviderInstallDestination]) -> [EcosystemPackage] {
        guard !targets.isEmpty else { return [] }
        let bundled = bundledCatalog()
        var byKey: [String: EcosystemPackage] = [:]
        for target in targets {
            for kind in EcosystemPackageKind.allCases {
                if kind == .plugin {
                    for pluginRoot in installedPluginRoots(at: URL(fileURLWithPath: target.pluginsPath, isDirectory: true)) {
                        guard let plugin = discoveredPluginPackage(
                            at: pluginRoot,
                            supportedProviderIDs: targets.map(\.id)
                        ) else { continue }
                        let key = "\(kind.rawValue)|\(Slug.make(from: plugin.id))"
                        byKey[key] = byKey[key] ?? plugin
                    }
                    continue
                }

                let root = URL(fileURLWithPath: target.path(for: kind), isDirectory: true)
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey]
                ) else { continue }
                for entry in entries {
                    let folderName = entry.lastPathComponent
                    if folderName.hasPrefix(".") { continue }
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
                        continue
                    }
                    let slug = folderName
                    let key = "\(kind.rawValue)|\(slug)"
                    if let bundledMatch = bundled.first(where: { $0.kind == kind && Slug.make(from: $0.name) == slug }) {
                        byKey[key] = bundledMatch
                        continue
                    }
                    if byKey[key] != nil { continue }
                    let summary = discoveredSummary(kind: kind, folderURL: entry)
                    byKey[key] = EcosystemPackage(
                        id: slug,
                        name: slug,
                        summary: summary,
                        kind: kind,
                        source: .local,
                        githubURL: nil,
                        defaultContents: "",
                        supportedProviders: targets.map(\.id)
                    )
                }
            }
        }
        return byKey.values.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func uninstallPackage(_ package: EcosystemPackage, on targets: [ProviderInstallDestination]) throws {
        for target in targets {
            if package.kind == .plugin {
                for root in installedPluginRoots(matching: package, on: target) {
                    try removeItemIfExists(at: root)
                }
                continue
            }
            try removeItemIfExists(at: packageURL(for: package, target: target))
        }
    }

    func installBundledPackage(_ package: EcosystemPackage, on targets: [ProviderInstallDestination]) throws -> [URL] {
        try targets.map { target in
            let packageURL = packageURL(for: package, target: target)
            try removeItemIfExists(at: packageURL)
            try createPackage(package, at: packageURL)
            return packageURL
        }
    }

    func createCustomSkill(named name: String, summary: String, on targets: [ProviderInstallDestination]) throws -> [URL] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CodebookError.malformedPrompt("Choose a name for the new skill.")
        }

        let package = EcosystemPackage(
            id: Slug.make(from: trimmedName),
            name: trimmedName,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .skill,
            source: .local,
            defaultContents: """
            # \(trimmedName)

            \(summary.isEmpty ? "Describe when to use this skill, what constraints matter, and what a good result looks like." : summary)
            """,
            supportedProviders: targets.map(\.id)
        )
        return try installBundledPackage(package, on: targets)
    }

    func installGitHubRepository(
        urlString: String,
        kind: EcosystemPackageKind,
        on targets: [ProviderInstallDestination]
    ) throws -> [URL] {
        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains("github.com") else {
            throw CodebookError.network("Enter a valid GitHub repository URL.")
        }

        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("codebook-github-\(UUID().uuidString)", isDirectory: true)
        SecureFileStore.prepareDirectory(tempRoot)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let cloneResult = try Shell.run(arguments: ["git", "clone", "--depth", "1", urlString, tempRoot.path])
        guard cloneResult.status == 0 else {
            throw CodebookError.network("Could not clone that GitHub repository.")
        }

        let repoName = repositoryName(from: url)
        let sourceURL = try candidateURL(for: kind, in: tempRoot)
        return try targets.map { target in
            let destinationURL = packageURL(
                for: EcosystemPackage(
                    id: repoName,
                    name: repoName,
                    summary: "",
                    kind: kind,
                    source: .github,
                    githubURL: urlString,
                    defaultContents: "",
                    supportedProviders: [target.id]
                ),
                target: target
            )
            try removeItemIfExists(at: destinationURL)
            try copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }

    private func builtInTargets() -> [ProviderInstallDestination] {
        [
            makeBuiltInTarget(id: IntegrationProvider.codex.rawValue, name: IntegrationProvider.codex.title, root: "~/.codex", systemImage: "terminal"),
            makeBuiltInTarget(id: IntegrationProvider.claude.rawValue, name: IntegrationProvider.claude.title, root: "~/.claude", systemImage: "text.bubble"),
            makeBuiltInTarget(id: IntegrationProvider.cursor.rawValue, name: IntegrationProvider.cursor.title, root: "~/.cursor", systemImage: "cursorarrow.rays"),
            makeBuiltInTarget(id: IntegrationProvider.copilot.rawValue, name: IntegrationProvider.copilot.title, root: "~/.copilot", systemImage: "sparkles"),
            makeBuiltInTarget(id: IntegrationProvider.opencode.rawValue, name: IntegrationProvider.opencode.title, root: "~/.opencode", systemImage: "chevron.left.forwardslash.chevron.right"),
            makeBuiltInTarget(id: IntegrationProvider.antigravity.rawValue, name: IntegrationProvider.antigravity.title, root: "~/.antigravity", systemImage: "paperplane")
        ]
    }

    private func makeBuiltInTarget(id: String, name: String, root: String, systemImage: String) -> ProviderInstallDestination {
        let expandedRoot = expandPath(root)
        return ProviderInstallDestination(
            id: id,
            name: name,
            systemImage: systemImage,
            rootPath: expandedRoot,
            skillsPath: expandedRoot + "/skills",
            pluginsPath: expandedRoot + "/plugins",
            mcpPath: expandedRoot + "/mcp",
            appsPath: expandedRoot + "/apps",
            isBuiltIn: true
        )
    }

    private func createPackage(_ package: EcosystemPackage, at url: URL) throws {
        switch package.kind {
        case .skill:
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let fileURL = url.appendingPathComponent("SKILL.md")
            try SecureFileStore.write(Data(package.defaultContents.utf8), to: fileURL)
        case .plugin:
            let metadataURL = url.appendingPathComponent(".codex-plugin/plugin.json")
            try SecureFileStore.write(Data(package.defaultContents.utf8), to: metadataURL)
        case .mcp:
            let manifestURL = url.appendingPathComponent("server.json")
            try SecureFileStore.write(Data(package.defaultContents.utf8), to: manifestURL)
        case .app:
            let manifestURL = url.appendingPathComponent("app.json")
            try SecureFileStore.write(Data(package.defaultContents.utf8), to: manifestURL)
        }
    }

    private func packageURL(for package: EcosystemPackage, target: ProviderInstallDestination) -> URL {
        URL(fileURLWithPath: target.path(for: package.kind), isDirectory: true)
            .appendingPathComponent(Slug.make(from: package.name), isDirectory: true)
    }

    private func installedPluginRoots(matching package: EcosystemPackage, on target: ProviderInstallDestination) -> [URL] {
        let pluginsRoot = URL(fileURLWithPath: target.pluginsPath, isDirectory: true)
        return installedPluginRoots(at: pluginsRoot).filter { pluginRootMatchesPackage($0, package: package) }
    }

    private func installedPluginRoots(at root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var pluginRoots: [URL] = []
        var seenPaths = Set<String>()

        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent == "plugin.json",
                  candidate.deletingLastPathComponent().lastPathComponent == ".codex-plugin" else {
                continue
            }

            let pluginRoot = candidate.deletingLastPathComponent().deletingLastPathComponent()
            if seenPaths.insert(pluginRoot.path).inserted {
                pluginRoots.append(pluginRoot)
            }
        }

        return pluginRoots.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func discoveredPluginPackage(at root: URL, supportedProviderIDs: [String]) -> EcosystemPackage? {
        let manifest = readPluginManifest(at: root)
        let displayName = manifest?.interface?.displayName?.nonEmpty
            ?? manifest?.name?.nonEmpty
            ?? root.lastPathComponent
        let summary = manifest?.interface?.shortDescription?.nonEmpty
            ?? manifest?.description?.nonEmpty
            ?? manifest?.interface?.longDescription?.nonEmpty
            ?? ""
        let id = manifest?.name?.nonEmpty ?? Slug.make(from: displayName)

        return EcosystemPackage(
            id: id,
            name: displayName,
            summary: String(summary.prefix(280)),
            kind: .plugin,
            source: .local,
            githubURL: nil,
            defaultContents: "",
            supportedProviders: supportedProviderIDs
        )
    }

    private func readPluginManifest(at root: URL) -> PluginManifest? {
        let metadataURL = root.appendingPathComponent(".codex-plugin/plugin.json")
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(PluginManifest.self, from: data)
    }

    private func pluginRootMatchesPackage(_ root: URL, package: EcosystemPackage) -> Bool {
        let packageIdentifiers = Set([
            package.id,
            Slug.make(from: package.id),
            Slug.make(from: package.name)
        ])

        let manifest = readPluginManifest(at: root)
        let pluginIdentifiers = Set([
            root.lastPathComponent,
            manifest?.name,
            manifest?.interface?.displayName
        ].compactMap { $0?.nonEmpty }.map(Slug.make))

        return !packageIdentifiers.isDisjoint(with: pluginIdentifiers)
    }

    private func discoveredSummary(kind: EcosystemPackageKind, folderURL: URL) -> String {
        switch kind {
        case .skill:
            let skillURL = folderURL.appendingPathComponent("SKILL.md")
            guard let data = try? Data(contentsOf: skillURL),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line.hasPrefix("#") { continue }
                if line.hasPrefix("---") { continue }
                return String(line.prefix(280))
            }
            return ""
        case .plugin, .mcp, .app:
            return ""
        }
    }

    private func candidateURL(for kind: EcosystemPackageKind, in cloneRoot: URL) throws -> URL {
        switch kind {
        case .skill:
            if fileManager.fileExists(atPath: cloneRoot.appendingPathComponent("SKILL.md").path) {
                return cloneRoot
            }
            if let nested = firstDirectory(in: cloneRoot, containing: "SKILL.md") {
                return nested
            }
        case .plugin:
            if fileManager.fileExists(atPath: cloneRoot.appendingPathComponent(".codex-plugin/plugin.json").path) {
                return cloneRoot
            }
        case .mcp:
            if fileManager.fileExists(atPath: cloneRoot.appendingPathComponent("server.json").path) {
                return cloneRoot
            }
        case .app:
            if fileManager.fileExists(atPath: cloneRoot.appendingPathComponent("app.json").path) {
                return cloneRoot
            }
        }
        return cloneRoot
    }

    private func firstDirectory(in root: URL, containing childPath: String) -> URL? {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for case let candidate as URL in enumerator {
            let fileURL = candidate.appendingPathComponent(childPath)
            if fileManager.fileExists(atPath: fileURL.path) {
                return candidate
            }
        }
        return nil
    }

    private func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func countEntries(at path: String, kind: EcosystemPackageKind? = nil) -> Int {
        if kind == .plugin {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            return installedPluginRoots(at: root).count
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return 0
        }
        return entries.filter { !$0.lastPathComponent.hasPrefix(".") }.count
    }

    private func removeItemIfExists(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func repositoryName(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        return raw.isEmpty ? "github-package" : raw
    }

    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/"), let home = environment["HOME"] {
            return home + String(path.dropFirst(1))
        }
        return NSString(string: path).expandingTildeInPath
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
