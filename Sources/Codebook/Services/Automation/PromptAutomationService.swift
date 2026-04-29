import CryptoKit
import Foundation

struct PromptAutomationService {
    private let fileManager = FileManager.default

    private struct PromptExportState: Codable {
        var files: [String: String] = [:]
    }

    func gitRoot(for repositoryPath: String) -> String? {
        repositoryRootURL(for: repositoryPath)?.path
    }

    func promptStoreURL(for repositoryPath: String, settings: RepoAutomationSettings) -> URL? {
        guard let gitRoot = gitRoot(for: repositoryPath) else { return nil }
        return resolvePath(settings.promptStorePath, relativeTo: gitRoot)
    }

    func ensurePromptStoreExists(for repositoryPath: String, settings: RepoAutomationSettings) throws -> URL {
        guard let storeURL = promptStoreURL(for: repositoryPath, settings: settings) else {
            throw CodebookError.invalidRepository(repositoryPath)
        }

        SecureFileStore.prepareDirectory(storeURL)
        return storeURL
    }

    func status(for repositoryPath: String, settings: RepoAutomationSettings, prompts: [ImportedPrompt]) -> RepoAutomationStatus? {
        guard let gitRoot = gitRoot(for: repositoryPath) else { return nil }
        let normalizedSettings = settings.normalized()
        let storeURL = resolvePath(normalizedSettings.promptStorePath, relativeTo: gitRoot)
        let manifestURL = promptManifestURL(for: gitRoot)
        let prepareHookURL = managedHookURL(for: gitRoot, mode: .prepareCommitMsg)
        let postHookURL = managedHookURL(for: gitRoot, mode: .postCommit)
        let auditHookURL = managedHookURL(for: gitRoot, mode: .commitMsg)
        let promptSubset = filteredPrompts(prompts, for: gitRoot, settings: normalizedSettings)
        let fingerprint = manifestFingerprint(at: manifestURL)
        let baseHooksInstalled = isManagedHook(at: prepareHookURL) && isManagedHook(at: postHookURL)
        let auditHookInstalled = !normalizedSettings.auditEnabled || isManagedHook(at: auditHookURL)

        return RepoAutomationStatus(
            gitRoot: gitRoot,
            promptStorePath: storeURL.path,
            promptStoreExists: fileManager.fileExists(atPath: storeURL.path),
            promptCount: dedupePrompts(promptSubset).count,
            hookInstalled: baseHooksInstalled && auditHookInstalled,
            auditEnabled: normalizedSettings.auditEnabled,
            autoExportEnabled: normalizedSettings.autoExportEnabled,
            trackedProviders: normalizedSettings.trackedProviders,
            promptFingerprint: fingerprint
        )
    }

    func installHooks(for repositoryPath: String, settings: RepoAutomationSettings) throws -> RepoAutomationStatus {
        guard let gitRoot = gitRoot(for: repositoryPath) else {
            throw CodebookError.invalidRepository(repositoryPath)
        }

        let normalizedSettings = settings.normalized()
        try installManagedHook(
            at: managedHookURL(for: gitRoot, mode: .prepareCommitMsg),
            script: prepareCommitMsgHookScript()
        )
        try installManagedHook(
            at: managedHookURL(for: gitRoot, mode: .postCommit),
            script: postCommitHookScript(
                gitRoot: gitRoot,
                promptStorePath: normalizedSettings.promptStorePath,
                exportMode: normalizedSettings.exportMode
            )
        )

        if normalizedSettings.auditEnabled {
            try installManagedHook(
                at: managedHookURL(for: gitRoot, mode: .commitMsg),
                script: commitMsgHookScript(auditEnabled: true)
            )
        } else {
            try uninstallManagedHook(at: managedHookURL(for: gitRoot, mode: .commitMsg))
        }

        return status(for: gitRoot, settings: normalizedSettings, prompts: [])
            ?? RepoAutomationStatus(
                gitRoot: gitRoot,
                promptStorePath: normalizedSettings.promptStorePath,
                promptStoreExists: false,
                promptCount: 0,
                hookInstalled: true,
                auditEnabled: normalizedSettings.auditEnabled,
                autoExportEnabled: normalizedSettings.autoExportEnabled,
                trackedProviders: normalizedSettings.trackedProviders,
                promptFingerprint: nil
            )
    }

    func uninstallHooks(for repositoryPath: String) throws {
        guard let gitRoot = gitRoot(for: repositoryPath) else {
            throw CodebookError.invalidRepository(repositoryPath)
        }

        try uninstallManagedHook(at: managedHookURL(for: gitRoot, mode: .prepareCommitMsg))
        try uninstallManagedHook(at: managedHookURL(for: gitRoot, mode: .postCommit))
        try uninstallManagedHook(at: managedHookURL(for: gitRoot, mode: .commitMsg))
    }

    func removePromptStore(for repositoryPath: String, settings: RepoAutomationSettings) throws {
        guard let gitRoot = gitRoot(for: repositoryPath) else {
            throw CodebookError.invalidRepository(repositoryPath)
        }

        let normalizedSettings = settings.normalized()
        let storeURL = resolvePath(normalizedSettings.promptStorePath, relativeTo: gitRoot)
        let manifestURL = promptManifestURL(for: gitRoot)
        let exportStateURL = promptExportStateURL(for: gitRoot)
        let codebookDirectoryURL = manifestURL.deletingLastPathComponent()

        try uninstallHooks(for: gitRoot)

        if fileManager.fileExists(atPath: storeURL.path) {
            try fileManager.removeItem(at: storeURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        if fileManager.fileExists(atPath: exportStateURL.path) {
            try fileManager.removeItem(at: exportStateURL)
        }
        if fileManager.fileExists(atPath: codebookDirectoryURL.path),
           (try? fileManager.contentsOfDirectory(atPath: codebookDirectoryURL.path).isEmpty) == true {
            try fileManager.removeItem(at: codebookDirectoryURL)
        }
    }

    func exportPrompts(_ prompts: [ImportedPrompt], to repositoryPath: String, settings: RepoAutomationSettings) throws -> PromptExportSummary {
        guard let gitRoot = gitRoot(for: repositoryPath) else {
            throw CodebookError.invalidRepository(repositoryPath)
        }

        let normalizedSettings = settings.normalized()
        let storeURL = try ensurePromptStoreExists(for: gitRoot, settings: normalizedSettings)
        let manifestDirectory = gitRootURL(for: gitRoot).appendingPathComponent(".codebook", isDirectory: true)
        SecureFileStore.prepareDirectory(manifestDirectory)
        let exportStateURL = promptExportStateURL(for: gitRoot)

        let exportablePrompts = filteredPrompts(prompts, for: gitRoot, settings: normalizedSettings)
        let dedupedPrompts = dedupePrompts(exportablePrompts)
        let exportState = loadPromptExportState(from: exportStateURL)
        let exportResult = try exportPromptFiles(
            dedupedPrompts,
            gitRoot: gitRoot,
            storeURL: storeURL,
            exportMode: normalizedSettings.exportMode,
            priorState: exportState
        )
        let exportedFiles = exportResult.files
        let exportedPaths = Set(exportedFiles.map { $0.standardizedFileURL.path })
        let previouslyTrackedPaths = Set(exportState.files.keys.map {
            storeURL.appendingPathComponent($0, isDirectory: false).standardizedFileURL.path
        })
        try removeOrphanedPromptExports(
            in: storeURL,
            keeping: exportedPaths,
            trackedPaths: previouslyTrackedPaths
        )
        try writePromptExportState(exportResult.state, to: exportStateURL)

        let fingerprint = bundleFingerprint(for: dedupedPrompts, gitRoot: gitRoot, settings: normalizedSettings)
        let manifestURL = promptManifestURL(for: gitRoot)
        try writeManifest(
            to: manifestURL,
            gitRoot: gitRoot,
            settings: normalizedSettings,
            fingerprint: fingerprint,
            promptCount: dedupedPrompts.count
        )

        return PromptExportSummary(
            gitRoot: gitRoot,
            promptStorePath: storeURL.path,
            exportedFiles: exportedFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
            manifestURL: manifestURL,
            fingerprint: fingerprint,
            promptCount: dedupedPrompts.count
        )
    }

    func syncConfiguredRepositories(
        prompts: [ImportedPrompt],
        settingsByGitRoot: [String: RepoAutomationSettings]
    ) throws -> [PromptExportSummary] {
        var summaries: [PromptExportSummary] = []

        for (gitRoot, settings) in settingsByGitRoot where settings.autoExportEnabled {
            let exports = try exportPrompts(prompts, to: gitRoot, settings: settings)
            summaries.append(exports)
        }

        return summaries
    }

    private func filteredPrompts(
        _ prompts: [ImportedPrompt],
        for gitRoot: String,
        settings: RepoAutomationSettings
    ) -> [ImportedPrompt] {
        let normalizedGitRoot = gitRootURL(for: gitRoot).path

        return prompts.filter { prompt in
            guard settings.trackedProviders.contains(prompt.provider) else { return false }
            if let promptGitRoot = prompt.gitRoot,
               gitRootURL(for: promptGitRoot).path == normalizedGitRoot {
                return true
            }
            if let projectPath = prompt.projectPath,
               gitRootURL(for: projectPath).path == normalizedGitRoot {
                return true
            }
            return gitRootURL(for: prompt.projectKey).path == normalizedGitRoot
        }
        .sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.id < rhs.id
            }
            return lhs.capturedAt < rhs.capturedAt
        }
    }

    private func dedupePrompts(_ prompts: [ImportedPrompt]) -> [ImportedPrompt] {
        var seen = Set<String>()
        return prompts.filter { prompt in
            seen.insert(promptFingerprint(for: prompt)).inserted
        }
    }

    private func promptFingerprint(for prompt: ImportedPrompt) -> String {
        let parts: [String] = [
            prompt.provider.rawValue,
            prompt.title,
            prompt.body,
            prompt.sourcePath,
            prompt.projectPath ?? "",
            prompt.gitRoot ?? "",
            String(Int64(prompt.capturedAt.timeIntervalSince1970))
        ]
        return sha256Hex(Data(parts.joined(separator: "\u{1f}").utf8))
    }

    private func bundleFingerprint(
        for prompts: [ImportedPrompt],
        gitRoot: String,
        settings: RepoAutomationSettings
    ) -> String {
        let promptHashes = prompts.map(promptFingerprint(for:))
        let payload = [
            gitRoot,
            settings.promptStorePath,
            settings.exportMode.rawValue,
            settings.trackedProviders.map(\.rawValue).sorted().joined(separator: ","),
            settings.auditEnabled ? "audit" : "no-audit",
            settings.autoExportEnabled ? "auto" : "manual",
            promptHashes.joined(separator: ",")
        ].joined(separator: "\u{1f}")
        return "codebook:sha256:\(sha256Hex(Data(payload.utf8)))"
    }

    private struct PromptExportBatchResult {
        let files: [URL]
        let state: PromptExportState
    }

    private func exportPromptFiles(
        _ prompts: [ImportedPrompt],
        gitRoot: String,
        storeURL: URL,
        exportMode: RepoAutomationExportMode,
        priorState: PromptExportState
    ) throws -> PromptExportBatchResult {
        var nextState = PromptExportState()

        switch exportMode {
        case .commit, .date:
            let promptsByDay = Dictionary(grouping: prompts) { promptDayKey(for: $0.effectiveDate) }
            let files = try promptsByDay.keys.sorted().map { dayKey in
                let groupedPrompts = promptsByDay[dayKey] ?? []
                let fileURL = dateFileURL(for: dayKey, storeURL: storeURL)
                let signature = exportSignature(for: groupedPrompts)
                nextState.files[fileURL.lastPathComponent] = signature
                if shouldRewriteExportFile(at: fileURL, signature: signature, priorState: priorState) {
                    try writeDateLog(groupedPrompts, dayKey: dayKey, gitRoot: gitRoot, to: fileURL)
                }
                return fileURL
            }
            return PromptExportBatchResult(files: files, state: nextState)
        case .thread:
            let promptsByThread = Dictionary(grouping: prompts, by: PromptThreading.key(for:))
            let files = try promptsByThread.keys.sorted().map { threadKey in
                let groupedPrompts = promptsByThread[threadKey] ?? []
                let fileURL = threadFileURL(for: threadKey, storeURL: storeURL)
                let signature = exportSignature(for: groupedPrompts)
                nextState.files[fileURL.lastPathComponent] = signature
                if shouldRewriteExportFile(at: fileURL, signature: signature, priorState: priorState) {
                    try writeThreadLog(groupedPrompts, threadKey: threadKey, gitRoot: gitRoot, to: fileURL)
                }
                return fileURL
            }
            return PromptExportBatchResult(files: files, state: nextState)
        }
    }

    private func shouldRewriteExportFile(at url: URL, signature: String, priorState: PromptExportState) -> Bool {
        let fileExists = fileManager.fileExists(atPath: url.path)
        let previousSignature = priorState.files[url.lastPathComponent]
        if !fileExists {
            // Only create the file if it has never been tracked before.
            // If it was previously tracked (has a prior signature) but is now missing
            // (e.g. deleted by a git rewrite), don't recreate it automatically.
            return previousSignature == nil
        }
        guard let previousSignature else { return false }
        return previousSignature != signature
    }

    private func exportSignature(for prompts: [ImportedPrompt]) -> String {
        let payload = prompts.map(promptFingerprint(for:)).sorted().joined(separator: ",")
        return sha256Hex(Data(payload.utf8))
    }

    private func commitFileURL(for commitSHA: String, storeURL: URL) -> URL {
        storeURL.appendingPathComponent("\(commitSHA).md", isDirectory: false)
    }

    private func dateFileURL(for dayKey: String, storeURL: URL) -> URL {
        storeURL.appendingPathComponent("date-\(dayKey).md", isDirectory: false)
    }

    private func threadFileURL(for threadKey: String, storeURL: URL) -> URL {
        let hash = sha256Hex(Data(threadKey.utf8))
        return storeURL.appendingPathComponent("thread-\(hash).md", isDirectory: false)
    }

    private func writeCommitLog(_ prompts: [ImportedPrompt], commitSHA: String, gitRoot: String, to url: URL) throws {
        let sortedPrompts = prompts.sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.capturedAt < rhs.capturedAt
        }

        var lines: [String] = []
        for (index, prompt) in sortedPrompts.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("## Prompt \(index + 1)")
            lines.append("")
            lines.append("```text")
            lines.append(prompt.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("```")
        }

        try SecureFileStore.write(Data(lines.joined(separator: "\n").utf8), to: url)
    }

    private func writeDateLog(_ prompts: [ImportedPrompt], dayKey: String, gitRoot: String, to url: URL) throws {
        let sortedPrompts = prompts.sorted { lhs, rhs in
            if lhs.effectiveDate == rhs.effectiveDate {
                return lhs.capturedAt < rhs.capturedAt
            }
            return lhs.effectiveDate < rhs.effectiveDate
        }
        var lines: [String] = []
        appendPromptEntries(sortedPrompts, to: &lines)
        try SecureFileStore.write(Data(lines.joined(separator: "\n").utf8), to: url)
    }

    private func writeThreadLog(_ prompts: [ImportedPrompt], threadKey: String, gitRoot: String, to url: URL) throws {
        let sortedPrompts = prompts.sorted { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.capturedAt < rhs.capturedAt
        }
        var lines: [String] = []
        appendPromptEntries(sortedPrompts, to: &lines)
        try SecureFileStore.write(Data(lines.joined(separator: "\n").utf8), to: url)
    }

    private func appendPromptEntries(_ prompts: [ImportedPrompt], to lines: inout [String]) {
        for (index, prompt) in prompts.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("## Prompt \(index + 1)")
            lines.append("")
            lines.append("```text")
            lines.append(prompt.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("```")
        }
    }

    private func removeOrphanedPromptExports(
        in storeURL: URL,
        keeping exportedPaths: Set<String>,
        trackedPaths: Set<String>
    ) throws {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }
        guard let enumerator = fileManager.enumerator(
            at: storeURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var directories: [URL] = []
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values.isDirectory == true {
                directories.append(itemURL)
                continue
            }
            guard values.isRegularFile == true,
                  itemURL.pathExtension.lowercased() == "md" else { continue }
            let standardizedPath = itemURL.standardizedFileURL.path
            guard !exportedPaths.contains(standardizedPath) else { continue }
            guard trackedPaths.contains(standardizedPath) || isManagedPromptExport(at: itemURL) else { continue }
            try fileManager.removeItem(at: itemURL)
        }

        for directoryURL in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if (try? fileManager.contentsOfDirectory(atPath: directoryURL.path).isEmpty) == true {
                try fileManager.removeItem(at: directoryURL)
            }
        }
    }

    private func isManagedPromptExport(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.hasPrefix("# Prompt Log")
    }

    private func promptExportStateURL(for gitRoot: String) -> URL {
        promptManifestURL(for: gitRoot)
            .deletingLastPathComponent()
            .appendingPathComponent("prompt-export-state.json", isDirectory: false)
    }

    private func loadPromptExportState(from url: URL) -> PromptExportState {
        guard let data = try? Data(contentsOf: url) else { return PromptExportState() }
        return (try? JSONDecoder().decode(PromptExportState.self, from: data)) ?? PromptExportState()
    }

    private func writePromptExportState(_ state: PromptExportState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        try writeDataIfChanged(data, to: url)
    }

    private func promptDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func currencyString(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount >= 1 ? 2 : 4
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.4f", amount)
    }

    private func writeManifest(
        to url: URL,
        gitRoot: String,
        settings: RepoAutomationSettings,
        fingerprint: String,
        promptCount: Int
    ) throws {
        let providers = settings.trackedProviders.map(\.rawValue).sorted().joined(separator: ",")
        let stableManifest = [
            "export CODEBOOK_PROMPT_LOG='\(shellSingleQuoted(fingerprint))'",
            "export CODEBOOK_PROMPT_SOURCE='\(shellSingleQuoted("codebook/\(URL(fileURLWithPath: gitRoot).lastPathComponent)"))'",
            "export CODEBOOK_PROMPT_STORE='\(shellSingleQuoted(settings.promptStorePath))'",
            "export CODEBOOK_PROMPT_EXPORT_MODE='\(shellSingleQuoted(settings.exportMode.rawValue))'",
            "export CODEBOOK_PROMPT_PROVIDERS='\(shellSingleQuoted(providers))'",
            "export CODEBOOK_PROMPT_COUNT='\(promptCount)'",
            "export CODEBOOK_PROMPT_AUDIT='\(settings.auditEnabled ? "true" : "false")'"
        ].joined(separator: "\n")

        if let existing = try? String(contentsOf: url, encoding: .utf8),
           normalizeManifest(existing) == stableManifest {
            return
        }

        let timestamp = Self.exportTimestampString(from: .now)
        let manifest = [
            stableManifest,
            "export CODEBOOK_PROMPT_UPDATED_AT='\(shellSingleQuoted(timestamp))'",
        ].joined(separator: "\n") + "\n"

        try writeDataIfChanged(Data(manifest.utf8), to: url)
    }

    private func normalizeManifest(_ contents: String) -> String {
        contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("export CODEBOOK_PROMPT_UPDATED_AT=") }
            .joined(separator: "\n")
    }

    private func writeDataIfChanged(_ data: Data, to url: URL) throws {
        if let existing = try? Data(contentsOf: url), existing == data {
            return
        }
        try SecureFileStore.write(data, to: url)
    }

    private func installManagedHook(at url: URL, script: String) throws {
        let backupURL = backupURL(for: url)
        let hookDirectory = url.deletingLastPathComponent()
        SecureFileStore.prepareDirectory(hookDirectory)

        if fileManager.fileExists(atPath: url.path), !isManagedHook(at: url) {
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: url, to: backupURL)
            } else {
                try fileManager.removeItem(at: url)
            }
        }

        try SecureFileStore.write(Data(script.utf8), to: url)
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func uninstallManagedHook(at url: URL) throws {
        let backupURL = backupURL(for: url)
        guard fileManager.fileExists(atPath: url.path) else { return }

        if isManagedHook(at: url) {
            try fileManager.removeItem(at: url)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: backupURL, to: url)
            }
        }
    }

    private func isManagedHook(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.contains("Managed by Codebook")
    }

    private func backupURL(for hookURL: URL) -> URL {
        hookURL.appendingPathExtension("codebook-backup")
    }

    private func managedHookURL(for gitRoot: String, mode: RepoAutomationHookMode) -> URL {
        let hooksPath = gitPath(for: gitRoot, path: "hooks") ?? gitRootURL(for: gitRoot).appendingPathComponent(".git", isDirectory: true).appendingPathComponent("hooks", isDirectory: true)
        let filename: String
        switch mode {
        case .prepareCommitMsg:
            filename = "prepare-commit-msg"
        case .postCommit:
            filename = "post-commit"
        case .commitMsg:
            filename = "commit-msg"
        }
        return hooksPath.appendingPathComponent(filename)
    }

    private func promptManifestURL(for gitRoot: String) -> URL {
        gitRootURL(for: gitRoot).appendingPathComponent(".codebook/prompt-manifest.sh")
    }

    private func gitRootURL(for gitRoot: String) -> URL {
        URL(fileURLWithPath: gitRoot).standardizedFileURL.resolvingSymlinksInPath()
    }

    private func gitPath(for gitRoot: String, path: String) -> URL? {
        gitCommonDirectoryURL(for: gitRoot)?.appendingPathComponent(path, isDirectory: true)
    }

    private func repositoryRootURL(for repositoryPath: String) -> URL? {
        let startingURL = URL(fileURLWithPath: repositoryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootCandidate = pathIsDirectory(startingURL.path)
            ? startingURL
            : startingURL.deletingLastPathComponent()

        var currentURL = rootCandidate
        while true {
            let gitMarkerURL = currentURL.appendingPathComponent(".git", isDirectory: false)
            if fileManager.fileExists(atPath: gitMarkerURL.path) {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                return nil
            }
            currentURL = parentURL
        }
    }

    private func gitDirectoryURL(for gitRoot: String) -> URL? {
        let gitMarkerURL = gitRootURL(for: gitRoot).appendingPathComponent(".git", isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitMarkerURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return gitMarkerURL
        }

        guard let contents = try? String(contentsOf: gitMarkerURL, encoding: .utf8) else {
            return nil
        }
        let prefix = "gitdir:"
        guard let line = contents.split(separator: "\n").map(String.init).first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else {
            return nil
        }

        let rawPath = line.trimmingCharacters(in: .whitespaces)
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }

        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath()
        }

        return gitMarkerURL.deletingLastPathComponent()
            .appendingPathComponent(rawPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func gitCommonDirectoryURL(for gitRoot: String) -> URL? {
        guard let gitDirectoryURL = gitDirectoryURL(for: gitRoot) else { return nil }

        let commondirURL = gitDirectoryURL.appendingPathComponent("commondir", isDirectory: false)
        guard let rawCommonDir = try? String(contentsOf: commondirURL, encoding: .utf8) else {
            return gitDirectoryURL
        }

        let trimmed = rawCommonDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return gitDirectoryURL
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath()
        }

        return gitDirectoryURL.appendingPathComponent(trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func pathIsDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func resolvePath(_ path: String, relativeTo gitRoot: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = gitRootURL(for: gitRoot)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return rootURL.appendingPathComponent(trimmed, isDirectory: true)
    }

    private func manifestFingerprint(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        for line in contents.split(separator: "\n") {
            guard line.hasPrefix("export CODEBOOK_PROMPT_LOG=") else { continue }
            let value = line.replacingOccurrences(of: "export CODEBOOK_PROMPT_LOG=", with: "")
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        return nil
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func prepareCommitMsgHookScript() -> String {
        """
        #!/bin/sh
        # Managed by Codebook
        set -eu

        if [ "${CODEBOOK_SKIP_HOOKS:-}" = "1" ]; then
            exit 0
        fi

        message_file="$1"
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        [ -n "$repo_root" ] || exit 0

        manifest="$repo_root/.codebook/prompt-manifest.sh"
        [ -f "$manifest" ] || exit 0

        . "$manifest"
        [ -n "${CODEBOOK_PROMPT_LOG:-}" ] || exit 0

        if grep -q '^Prompt-Log:' "$message_file" 2>/dev/null; then
            exit 0
        fi

        tmp="${message_file}.codebook"
        cat "$message_file" > "$tmp"
        printf '\nPrompt-Log: %s\n' "$CODEBOOK_PROMPT_LOG" >> "$tmp"

        if [ -n "${CODEBOOK_PROMPT_SOURCE:-}" ]; then
            printf 'Prompt-Source: %s\n' "$CODEBOOK_PROMPT_SOURCE" >> "$tmp"
        fi

        mv "$tmp" "$message_file"
        """
    }

    private func postCommitHookScript(gitRoot: String, promptStorePath: String, exportMode: RepoAutomationExportMode) -> String {
        // Prompt exports are written continuously by the app on each refresh cycle.
        // The prompts/ directory is kept up to date in the working tree so changes
        // are naturally included in the next commit — no export or amend needed here.
        return """
        #!/bin/sh
        # Managed by Codebook
        exit 0
        """
    }

    private func commitMsgHookScript(auditEnabled: Bool) -> String {
        """
        #!/bin/sh
        # Managed by Codebook
        set -eu

        if [ "\(auditEnabled ? "true" : "false")" != "true" ]; then
            exit 0
        fi

        message_file="$1"
        if grep -q '^Prompt-Log:' "$message_file" 2>/dev/null; then
            exit 0
        fi

        printf 'Codebook audit is enabled, but the Prompt-Log trailer is missing.\\n' >&2
        exit 1
        """
    }

    private static func exportTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
