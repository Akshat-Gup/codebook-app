import Foundation
import SQLite3

struct IntegrationScanProgress: Sendable {
    let completedProviders: Int
    let totalProviders: Int
    let latestProvider: IntegrationProvider?
    let latestPrompts: [ImportedPrompt]
}

struct IntegrationScanner: Sendable {
    private static let runtimeLogger = RuntimeLogger.shared
    static let cacheVersion = 17
    private static let parserVersion = cacheVersion
    private static let streamedReadChunkSize = 64 * 1024

    func scanAll(
        enabledProviders: Set<IntegrationProvider> = Set(IntegrationProvider.allCases),
        forceRescan: Bool = false,
        progress: (@Sendable (IntegrationScanProgress) async -> Void)? = nil
    ) async -> [ImportedPrompt] {
        Self.runtimeLogger.info("Integration scan started")
        let cacheStore = IntegrationScanCacheStore()
        let existingCache = forceRescan ? [:] : cacheStore.load()
        let totalProviders = enabledProviders.count
        if let progress {
            await progress(
                IntegrationScanProgress(
                    completedProviders: 0,
                    totalProviders: totalProviders,
                    latestProvider: nil,
                    latestPrompts: []
                )
            )
        }
        let providerResults = await withTaskGroup(of: ProviderScanResult.self) { group in
            if enabledProviders.contains(.codex) {
                group.addTask { Self.scanCodex(cache: existingCache) }
            }
            if enabledProviders.contains(.claude) {
                group.addTask { Self.scanClaude(cache: existingCache) }
            }
            if enabledProviders.contains(.cursor) {
                group.addTask { Self.scanCursor(cache: existingCache) }
            }
            if enabledProviders.contains(.copilot) {
                group.addTask { Self.scanCopilot(cache: existingCache) }
            }
            if enabledProviders.contains(.opencode) {
                group.addTask { Self.scanOpenCode(cache: existingCache) }
            }
            if enabledProviders.contains(.antigravity) {
                group.addTask { Self.scanAntigravityBrainTasks(cache: existingCache) }
            }

            var results: [IntegrationProvider: ProviderScanResult] = [:]
            for await result in group {
                results[result.provider] = result
                if let progress {
                    await progress(
                        IntegrationScanProgress(
                            completedProviders: results.count,
                            totalProviders: totalProviders,
                            latestProvider: result.provider,
                            latestPrompts: result.prompts
                        )
                    )
                }
                Self.runtimeLogger.info("Scanned integration provider", metadata: [
                    "provider": result.provider.rawValue,
                    "count": "\(result.prompts.count)",
                    "cacheHits": "\(result.cacheHits)",
                    "parsed": "\(result.parsedCount)"
                ])
            }
            return results
        }

        let codexResults = providerResults[.codex]?.prompts ?? []
        let claudeResults = providerResults[.claude]?.prompts ?? []
        let cursorResults = providerResults[.cursor]?.prompts ?? []
        let copilotResults = providerResults[.copilot]?.prompts ?? []
        let opencodeResults = providerResults[.opencode]?.prompts ?? []
        let antigravityResults = providerResults[.antigravity]?.prompts ?? []
        let imports = codexResults + claudeResults + cursorResults + copilotResults + opencodeResults + antigravityResults
        var seen = Set<PromptDedupKey>()
        let deduped = imports.filter { item in
            let key = PromptDedupKey(
                provider: item.provider,
                title: item.title,
                body: item.body,
                sourcePath: item.sourcePath
            )
            return seen.insert(key).inserted
        }
        .sorted { $0.capturedAt > $1.capturedAt }
        let refreshedCache = providerResults.values.reduce(into: [String: IntegrationScanCacheStore.Entry]()) { partialResult, result in
            partialResult.merge(result.cacheEntries, uniquingKeysWith: { _, new in new })
        }
        cacheStore.save(refreshedCache)
        Self.runtimeLogger.info("Integration scan completed", metadata: [
            "codex": "\(codexResults.count)",
            "claude": "\(claudeResults.count)",
            "cursor": "\(cursorResults.count)",
            "copilot": "\(copilotResults.count)",
            "opencode": "\(opencodeResults.count)",
            "antigravity": "\(antigravityResults.count)",
            "total": "\(deduped.count)"
        ])
        return deduped
    }

    static func scanAllPromptsForTesting(
        homeDirectoryURL: URL,
        enabledProviders: Set<IntegrationProvider> = Set(IntegrationProvider.allCases)
    ) -> [ImportedPrompt] {
        var imports: [ImportedPrompt] = []
        if enabledProviders.contains(.codex) {
            imports += scanCodexPromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }
        if enabledProviders.contains(.claude) {
            imports += scanClaudePromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }
        if enabledProviders.contains(.cursor) {
            imports += scanCursorPromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }
        if enabledProviders.contains(.copilot) {
            imports += scanCopilotPromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }
        if enabledProviders.contains(.opencode) {
            imports += scanOpenCodePromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }
        if enabledProviders.contains(.antigravity) {
            imports += scanAntigravityPromptsForTesting(homeDirectoryURL: homeDirectoryURL)
        }

        var seen = Set<PromptDedupKey>()
        return imports
            .filter { item in
                let key = PromptDedupKey(
                    provider: item.provider,
                    title: item.title,
                    body: item.body,
                    sourcePath: item.sourcePath
                )
                return seen.insert(key).inserted
            }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func scanCodex(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        let fileManager = FileManager.default
        var allPrompts: [ImportedPrompt] = []
        var allCacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var totalCacheHits = 0
        var totalParsed = 0
        var scannedPaths = Set<String>()

        // 1. Live threads via state DB
        let liveResult = scanLiveCodexThreads(cache: cache)
        allPrompts += liveResult.prompts
        allCacheEntries.merge(liveResult.cacheEntries, uniquingKeysWith: { _, new in new })
        totalCacheHits += liveResult.cacheHits
        totalParsed += liveResult.parsedCount
        scannedPaths.formUnion(liveResult.scannedSourcePaths)

        // 2. Sessions directory fallback for files not already covered by the state DB
        let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions", isDirectory: true)
        if fileManager.fileExists(atPath: sessionsRoot.path) {
            let enumerator = fileManager.enumerator(at: sessionsRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            var sessionFiles: [URL] = []

            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "jsonl" else { continue }
                let standardizedPath = fileURL.resolvingSymlinksInPath().path
                guard !scannedPaths.contains(standardizedPath) else { continue }
                sessionFiles.append(fileURL)
                scannedPaths.insert(standardizedPath)
            }

            let sessionsResult = scanFiles(provider: .codex, files: sessionFiles, cache: cache) { fileURL in
                parseCodexTranscript(fileURL)
            }
            allPrompts += sessionsResult.prompts
            allCacheEntries.merge(sessionsResult.cacheEntries, uniquingKeysWith: { _, new in new })
            totalCacheHits += sessionsResult.cacheHits
            totalParsed += sessionsResult.parsedCount
        }

        // 3. Archived sessions — always scanned regardless of whether the state DB had results
        let archivedRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        if fileManager.fileExists(atPath: archivedRoot.path) {
            let files = (try? fileManager.contentsOfDirectory(at: archivedRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
            let archivedResult = scanFiles(provider: .codex, files: jsonlFiles, cache: cache) { fileURL in
                parseCodexTranscript(fileURL)
            }
            allPrompts += archivedResult.prompts
            allCacheEntries.merge(archivedResult.cacheEntries, uniquingKeysWith: { _, new in new })
            totalCacheHits += archivedResult.cacheHits
            totalParsed += archivedResult.parsedCount
        }

        // 4. CLI prompt history fallback for prompts that never made it into rollout transcripts.
        let historyURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/history.jsonl", isDirectory: false)
        if fileManager.fileExists(atPath: historyURL.path) {
            let historyResult = scanFiles(provider: .codex, files: [historyURL], cache: cache, parser: parseCodexHistory)
            allPrompts = mergeCodexHistoryPrompts(primary: allPrompts, history: historyResult.prompts)
            allCacheEntries.merge(historyResult.cacheEntries, uniquingKeysWith: { _, new in new })
            totalCacheHits += historyResult.cacheHits
            totalParsed += historyResult.parsedCount
        }

        return ProviderScanResult(
            provider: .codex,
            prompts: allPrompts,
            cacheEntries: allCacheEntries,
            cacheHits: totalCacheHits,
            parsedCount: totalParsed
        )
    }

    /// Test-facing entry point that scans all Codex sources from a given home directory.
    /// Merges live threads (state DB), sessions directory, and archived sessions.
    /// Tracks which paths were covered by the state DB to avoid double-scanning.
    static func scanCodexPromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        let fileManager = FileManager.default
        var allPrompts: [ImportedPrompt] = []
        var scannedPaths = Set<String>()

        // 1. Live threads via state DB
        if let stateDBURL = discoverCodexStateDatabase(homeURL: homeDirectoryURL),
           let threads = loadCodexThreads(from: stateDBURL) {
            for thread in threads where fileManager.fileExists(atPath: thread.rolloutURL.path) {
                allPrompts += parseCodexTranscript(thread.rolloutURL, fallbackProjectPath: thread.cwd, sourceContextID: thread.id)
                scannedPaths.insert(thread.rolloutURL.resolvingSymlinksInPath().path)
            }
        }

        // 2. Sessions directory (files not already covered by the state DB)
        let sessionsRoot = homeDirectoryURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        if fileManager.fileExists(atPath: sessionsRoot.path) {
            let enumerator = fileManager.enumerator(at: sessionsRoot, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "jsonl",
                      !scannedPaths.contains(fileURL.resolvingSymlinksInPath().path) else { continue }
                allPrompts += parseCodexTranscript(fileURL)
            }
        }

        // 3. Archived sessions (recursive enumeration to handle nested date-based directories)
        let archivedRoot = homeDirectoryURL.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        if fileManager.fileExists(atPath: archivedRoot.path) {
            let enumerator = fileManager.enumerator(at: archivedRoot, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "jsonl" else { continue }
                allPrompts += parseCodexTranscript(fileURL)
            }
        }

        let historyURL = homeDirectoryURL.appendingPathComponent(".codex/history.jsonl", isDirectory: false)
        if fileManager.fileExists(atPath: historyURL.path) {
            allPrompts = mergeCodexHistoryPrompts(primary: allPrompts, history: parseCodexHistory(historyURL))
        }

        return allPrompts
    }

    static func parseCodexTranscript(_ url: URL, fallbackProjectPath: String? = nil, sourceContextID: String? = nil) -> [ImportedPrompt] {
        var imports: [ImportedPrompt] = []
        var currentProjectPath: String? = normalizedProjectPath(fallbackProjectPath)
        var currentModelID: String?
        var seenMessages = Set<String>()
        var latestUsageTotals: UsageTotals?
        var pendingPromptIndex: Int?
        var pendingPromptUsageBaseline: UsageTotals?
        let contextID = sourceContextID ?? url.path

        forEachJSONObjectLine(in: url) { object in
            guard let timestamp = object["timestamp"] as? String,
                  let date = DateFormatting.parse(timestamp)
            else { return }

            if let type = object["type"] as? String,
               (type == "session_meta" || type == "turn_context"),
               let payload = object["payload"] as? [String: Any],
               let cwd = payload["cwd"] as? String {
                currentProjectPath = normalizedProjectPath(cwd)
                currentModelID = payload["model"] as? String ?? currentModelID
            }

            if let type = object["type"] as? String, type == "response_item",
               let payload = object["payload"] as? [String: Any],
               let messageType = payload["type"] as? String,
               messageType == "message",
               let role = payload["role"] as? String,
               role == "user",
               let content = payload["content"] as? [[String: Any]] {
                let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard isLikelyCodexPrompt(text) else { return }
                let dedupeKey = "\(Int64(date.timeIntervalSince1970))|\(text)"
                guard seenMessages.insert(dedupeKey).inserted else { return }
                imports.append(ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .codex,
                    title: cleanPromptTitle(text.components(separatedBy: .newlines).first ?? "Codex Prompt"),
                    body: text,
                    sourcePath: url.path,
                    projectPath: currentProjectPath,
                    capturedAt: date,
                    metadataOnly: false,
                    sourceContextID: contextID,
                    modelID: currentModelID
                ))
                pendingPromptIndex = imports.indices.last
                pendingPromptUsageBaseline = latestUsageTotals
            }

            if let type = object["type"] as? String, type == "event_msg",
               let payload = object["payload"] as? [String: Any],
               let eventType = payload["type"] as? String,
               eventType == "user_message",
               let message = payload["message"] as? String {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isLikelyCodexPrompt(trimmed) else { return }
                let dedupeKey = "\(Int64(date.timeIntervalSince1970))|\(trimmed)"
                guard seenMessages.insert(dedupeKey).inserted else { return }
                imports.append(ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .codex,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Codex Prompt"),
                    body: trimmed,
                    sourcePath: url.path,
                    projectPath: currentProjectPath,
                    capturedAt: date,
                    metadataOnly: false,
                    sourceContextID: contextID,
                    modelID: currentModelID
                ))
                pendingPromptIndex = imports.indices.last
                pendingPromptUsageBaseline = latestUsageTotals
            }

            if let type = object["type"] as? String, type == "event_msg",
               let payload = object["payload"] as? [String: Any],
               let eventType = payload["type"] as? String,
               eventType == "token_count",
               let info = payload["info"] as? [String: Any],
               let totalUsage = usageTotals(from: info["total_token_usage"]) {
                latestUsageTotals = totalUsage

                if let pendingPromptIndex {
                    applyUsageDelta(from: pendingPromptUsageBaseline, to: totalUsage, on: &imports[pendingPromptIndex])
                    if imports[pendingPromptIndex].modelID == nil {
                        imports[pendingPromptIndex].modelID = currentModelID
                    }
                }
            }
        }

        return imports
    }

    private static func parseCodexHistory(_ url: URL) -> [ImportedPrompt] {
        var prompts: [ImportedPrompt] = []
        forEachJSONObjectLine(in: url) { object in
            guard let text = object["text"] as? String else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isLikelyCodexPrompt(trimmed) else { return }

            let timestampSeconds = (object["ts"] as? NSNumber)?.doubleValue
                ?? (object["ts"] as? Double)
                ?? Double(integerValue(object["ts"]) ?? 0)
            let capturedAt = timestampSeconds > 0 ? Date(timeIntervalSince1970: timestampSeconds) : .distantPast

            prompts.append(
                ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .codex,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Codex Prompt"),
                    body: trimmed,
                    sourcePath: url.path,
                    projectPath: nil,
                    capturedAt: capturedAt,
                    metadataOnly: false,
                    sourceContextID: object["session_id"] as? String
                )
            )
        }
        return prompts
    }

    private static func scanLiveCodexThreads(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        guard let stateDBURL = discoverCodexStateDatabase() else {
            return ProviderScanResult(provider: .codex)
        }
        guard let threads = loadCodexThreads(from: stateDBURL), !threads.isEmpty else {
            return ProviderScanResult(provider: .codex)
        }

        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0
        var scannedSourcePaths = Set<String>()

        for thread in threads {
            scannedSourcePaths.insert(thread.rolloutURL.resolvingSymlinksInPath().path)
            let cacheKey = "v\(parserVersion):codex-thread:\(thread.id)"
            guard let fingerprint = codexThreadFingerprint(thread: thread) else { continue }
            if let cached = cache[cacheKey], cached.fingerprint == fingerprint {
                prompts.append(contentsOf: cached.prompts)
                cacheEntries[cacheKey] = cached
                cacheHits += 1
                continue
            }

            let parsed = parseCodexTranscript(thread.rolloutURL, fallbackProjectPath: thread.cwd, sourceContextID: thread.id)
            prompts.append(contentsOf: parsed)
            cacheEntries[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
            parsedCount += 1
        }

        return ProviderScanResult(
            provider: .codex,
            prompts: prompts,
            cacheEntries: cacheEntries,
            cacheHits: cacheHits,
            parsedCount: parsedCount,
            scannedSourcePaths: scannedSourcePaths
        )
    }

    private static func scanClaude(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        let fileManager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let root = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let historyURL = home.appendingPathComponent(".claude/history.jsonl", isDirectory: false)

        guard fileManager.fileExists(atPath: root.path) || fileManager.fileExists(atPath: historyURL.path) else {
            return ProviderScanResult(provider: .claude)
        }

        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        if fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
            var files: [URL] = []

            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "jsonl" else { continue }
                files.append(fileURL)
            }

            let projectResult = scanFiles(provider: .claude, files: files, cache: cache) { fileURL in
                parseClaudeSession(fileURL)
            }
            prompts += projectResult.prompts
            cacheEntries.merge(projectResult.cacheEntries, uniquingKeysWith: { _, new in new })
            cacheHits += projectResult.cacheHits
            parsedCount += projectResult.parsedCount
        }

        if fileManager.fileExists(atPath: historyURL.path) {
            let historyResult = scanFiles(provider: .claude, files: [historyURL], cache: cache) { fileURL in
                parseClaudeHistory(fileURL)
            }
            prompts += historyResult.prompts
            cacheEntries.merge(historyResult.cacheEntries, uniquingKeysWith: { _, new in new })
            cacheHits += historyResult.cacheHits
            parsedCount += historyResult.parsedCount
        }

        return ProviderScanResult(
            provider: .claude,
            prompts: prompts,
            cacheEntries: cacheEntries,
            cacheHits: cacheHits,
            parsedCount: parsedCount
        )
    }

    static func parseClaudeSession(_ url: URL) -> [ImportedPrompt] {
        var imports: [ImportedPrompt] = []
        let fallbackProjectPath = decodeClaudeProjectPath(from: url)
        let sessionID = claudeSessionID(from: url)
        var pendingPromptIndex: Int?
        var usageByRequestID: [String: UsageTotals] = [:]

        forEachJSONObjectLine(in: url) { object in
            guard let type = object["type"] as? String,
                  let timestamp = object["timestamp"] as? String,
                  let date = DateFormatting.parse(timestamp)
            else { return }

            if type == "user",
               let message = object["message"] as? [String: Any],
               let role = message["role"] as? String,
               role == "user",
               let content = claudeUserMessageText(from: message["content"]) {
                let cwd = object["cwd"] as? String
                let projectPath = preferredClaudeProjectPath(cwd: cwd, fallback: fallbackProjectPath)
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { return }
                imports.append(ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .claude,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Claude Prompt"),
                    body: trimmed,
                    sourcePath: url.path,
                    projectPath: projectPath,
                    capturedAt: date,
                    metadataOnly: false,
                    sourceContextID: sessionID ?? url.path
                ))
                pendingPromptIndex = imports.indices.last
                return
            }

            guard type == "assistant",
                  let pendingPromptIndex,
                  let message = object["message"] as? [String: Any]
            else { return }

            if let modelID = message["model"] as? String, imports[pendingPromptIndex].modelID == nil {
                imports[pendingPromptIndex].modelID = modelID
            }

            guard let usage = usageTotals(fromClaudeUsage: message["usage"]) else { return }

            let resolvedUsage: UsageTotals
            if let requestID = object["requestId"] as? String {
                let preferred = preferredUsageTotals(usageByRequestID[requestID], usage)
                usageByRequestID[requestID] = preferred
                resolvedUsage = preferred
            } else {
                resolvedUsage = usage
            }

            applyMeasuredUsage(resolvedUsage, on: &imports[pendingPromptIndex])
        }

        return imports
    }

    private static func claudeUserMessageText(from payload: Any?) -> String? {
        if let content = payload as? String {
            return content
        }

        guard let blocks = payload as? [[String: Any]] else { return nil }
        let textBlocks = blocks.compactMap { block -> String? in
            guard let type = block["type"] as? String,
                  type == "text",
                  let text = block["text"] as? String
            else {
                return nil
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !textBlocks.isEmpty else { return nil }
        return textBlocks.joined(separator: "\n\n")
    }

    private static func parseClaudeHistory(_ url: URL) -> [ImportedPrompt] {
        var prompts: [ImportedPrompt] = []
        forEachJSONObjectLine(in: url) { object in
            guard let display = object["display"] as? String else { return }

            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("/"),
                  isLikelyUserPrompt(trimmed)
            else {
                return
            }

            let timestampMS = (object["timestamp"] as? NSNumber)?.doubleValue
            let capturedAt = timestampMS.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? .distantPast
            let projectPath = (object["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceContextID = object["sessionId"] as? String

            prompts.append(
                ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .claude,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Claude Prompt"),
                    body: trimmed,
                    sourcePath: url.path,
                    projectPath: projectPath?.isEmpty == false ? projectPath : nil,
                    capturedAt: capturedAt,
                    metadataOnly: false,
                    sourceContextID: sourceContextID
                )
            )
        }
        return prompts
    }

    static func scanClaudePromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        let fileManager = FileManager.default
        let root = homeDirectoryURL.appendingPathComponent(".claude/projects", isDirectory: true)
        let historyURL = homeDirectoryURL.appendingPathComponent(".claude/history.jsonl", isDirectory: false)
        var prompts: [ImportedPrompt] = []

        if fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
            var files: [URL] = []

            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "jsonl" else { continue }
                files.append(fileURL)
            }

            prompts += files.flatMap(parseClaudeSession)
        }

        if fileManager.fileExists(atPath: historyURL.path) {
            prompts += parseClaudeHistory(historyURL)
        }

        return prompts
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func scanCursor(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        scanCursor(homeDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()), cache: cache)
    }

    private static func scanCursor(
        homeDirectoryURL: URL,
        cache: [String: IntegrationScanCacheStore.Entry]
    ) -> ProviderScanResult {
        let fileManager = FileManager.default
        let root = homeDirectoryURL.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else {
            return ProviderScanResult(provider: .cursor)
        }
        let workspaceDirs = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        // composerId → project path mapping, built as we visit each workspace DB
        var composerProjectMap: [String: String?] = [:]

        for dir in workspaceDirs {
            let dbURL = dir.appendingPathComponent("state.vscdb")
            guard fileManager.fileExists(atPath: dbURL.path) else { continue }
            let workspaceJSON = dir.appendingPathComponent("workspace.json")
            let projectPath = parseWorkspacePath(workspaceJSON)

            // Build composerId → projectPath mapping from workspace-level composer metadata
            if let db = try? openSQLite(dbURL) {
                if let composerDataStr = fetchItemValue(db: db, key: "composer.composerData"),
                   let data = composerDataStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let composers = obj["allComposers"] as? [[String: Any]] {
                    for composer in composers {
                        if let composerId = composer["composerId"] as? String {
                            composerProjectMap[composerId] = projectPath
                        }
                    }
                }
                sqlite3_close(db)
            }

            let cacheKey = sourceCacheKey(provider: .cursor, sourcePath: dbURL.path)
            let fingerprint = compositeFingerprint(for: [dbURL, workspaceJSON])
            if let fingerprint,
               let cached = cache[cacheKey],
               cached.fingerprint == fingerprint {
                prompts.append(contentsOf: cached.prompts)
                cacheEntries[cacheKey] = cached
                cacheHits += 1
                continue
            }

            let parsed = parseCursorDatabase(dbURL, projectPath: projectPath)
            prompts.append(contentsOf: parsed)
            if let fingerprint {
                cacheEntries[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
            }
            parsedCount += 1
        }

        // Scan global cursorDiskKV for composer/agent conversations (the main source of missing prompts)
        let composerResult = scanCursorComposerConversations(cache: cache, composerProjectMap: composerProjectMap)
        cacheEntries.merge(composerResult.cacheEntries, uniquingKeysWith: { _, new in new })
        cacheHits += composerResult.cacheHits
        parsedCount += composerResult.parsedCount

        // Deduplicate between aiService.prompts and composer conversations by body text,
        // keeping the richer copy when Cursor stores the same prompt twice.
        var preferredPromptByBody: [String: ImportedPrompt] = [:]
        var orderedBodies: [String] = []

        for prompt in prompts + composerResult.prompts {
            if preferredPromptByBody[prompt.body] == nil {
                orderedBodies.append(prompt.body)
                preferredPromptByBody[prompt.body] = prompt
                continue
            }

            if let existing = preferredPromptByBody[prompt.body] {
                preferredPromptByBody[prompt.body] = preferredImportedPrompt(existing, prompt)
            }
        }

        prompts = orderedBodies.compactMap { preferredPromptByBody[$0] }

        return ProviderScanResult(
            provider: .cursor,
            prompts: prompts,
            cacheEntries: cacheEntries,
            cacheHits: cacheHits,
            parsedCount: parsedCount
        )
    }

    static func scanCursorPromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        scanCursor(homeDirectoryURL: homeDirectoryURL, cache: [:]).prompts
    }

    private static func scanCursorComposerConversations(
        cache: [String: IntegrationScanCacheStore.Entry],
        composerProjectMap: [String: String?]
    ) -> ProviderScanResult {
        let globalDBURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: globalDBURL.path) else {
            return ProviderScanResult(provider: .cursor)
        }

        let cacheKey = sourceCacheKey(provider: .cursor, sourcePath: globalDBURL.path + ":composerKV")
        let fingerprint = fileFingerprint(for: globalDBURL)
        if let fingerprint,
           let cached = cache[cacheKey],
           cached.fingerprint == fingerprint {
            return ProviderScanResult(
                provider: .cursor,
                prompts: cached.prompts,
                cacheEntries: [cacheKey: cached],
                cacheHits: 1,
                parsedCount: 0
            )
        }

        let parsed = parseCursorComposerConversations(globalDBURL, composerProjectMap: composerProjectMap)
        var updatedCache: [String: IntegrationScanCacheStore.Entry] = [:]
        if let fingerprint {
            updatedCache[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
        }
        return ProviderScanResult(
            provider: .cursor,
            prompts: parsed,
            cacheEntries: updatedCache,
            cacheHits: 0,
            parsedCount: 1
        )
    }

    private static func parseCursorComposerConversations(
        _ globalDBURL: URL,
        composerProjectMap: [String: String?]
    ) -> [ImportedPrompt] {
        guard let db = try? openSQLite(globalDBURL) else {
            Self.runtimeLogger.error("Failed to open Cursor global store", metadata: ["path": globalDBURL.path])
            return []
        }
        defer { sqlite3_close(db) }

        // Step 1: Read all composerData entries to collect (composerId, userBubbleIds, createdAt)
        var statement: OpaquePointer?
        let sql = "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%';"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        struct ComposerEntry {
            let composerId: String
            let modelID: String?
            let bubbleHeaders: [[String: Any]]
            let userBubbleIds: [String]
            let createdAt: Date?
            let inferredProjectPath: String?
        }

        var composerEntries: [ComposerEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyCString = sqlite3_column_text(statement, 0),
                  let valueCString = sqlite3_column_text(statement, 1) else { continue }
            let key = String(cString: keyCString)
            guard key.hasPrefix("composerData:") else { continue }
            let composerId = String(key.dropFirst("composerData:".count))
            let valueStr = String(cString: valueCString)
            guard let data = valueStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let rawHeaders = obj["fullConversationHeadersOnly"] as? [[String: Any]] ?? []
            let userBubbleIds = rawHeaders.compactMap { h -> String? in
                guard let type = h["type"] as? Int, type == 1,
                      let bubbleId = h["bubbleId"] as? String else { return nil }
                return bubbleId
            }
            guard !userBubbleIds.isEmpty else { continue }

            let createdAt = (obj["createdAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000.0)
            }
            composerEntries.append(ComposerEntry(
                composerId: composerId,
                modelID: cursorComposerModelID(from: obj),
                bubbleHeaders: rawHeaders,
                userBubbleIds: userBubbleIds,
                createdAt: createdAt,
                inferredProjectPath: cursorComposerProjectPath(from: obj)
            ))
        }

        // Step 2: For each composer's user bubbles, fetch the text from cursorDiskKV
        var imports: [ImportedPrompt] = []
        for entry in composerEntries {
            let projectPath = composerProjectMap[entry.composerId] ?? entry.inferredProjectPath
            let fallbackDate = entry.createdAt ?? .now
            let metricsByUserBubbleID = cursorComposerMetricsByUserBubbleID(
                db: db,
                composerId: entry.composerId,
                headers: entry.bubbleHeaders
            )

            for bubbleId in entry.userBubbleIds {
                let bubbleKey = "bubbleId:\(entry.composerId):\(bubbleId)"
                guard let text = fetchCursorDiskKVText(db: db, key: bubbleKey) else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { continue }
                let metrics = metricsByUserBubbleID[bubbleId]
                imports.append(ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .cursor,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Cursor Prompt"),
                    body: trimmed,
                    sourcePath: globalDBURL.path,
                    projectPath: projectPath,
                    capturedAt: fallbackDate,
                    metadataOnly: false,
                    sourceContextID: entry.composerId,
                    modelID: entry.modelID,
                    inputTokens: metrics?.usage?.inputTokens,
                    cachedInputTokens: nil,
                    outputTokens: metrics?.usage?.outputTokens,
                    totalTokens: metrics?.usage.map { max(0, $0.inputTokens + $0.outputTokens) },
                    responseTimeMs: metrics?.responseTimeMs
                ))
            }
        }

        Self.runtimeLogger.info("Parsed Cursor composer conversations", metadata: [
            "composers": "\(composerEntries.count)",
            "prompts": "\(imports.count)"
        ])
        return imports
    }

    static func parseCursorComposerConversationsForTesting(
        _ globalDBURL: URL,
        composerProjectMap: [String: String?] = [:]
    ) -> [ImportedPrompt] {
        parseCursorComposerConversations(globalDBURL, composerProjectMap: composerProjectMap)
    }

    private static func cursorComposerModelID(from object: [String: Any]) -> String? {
        if let modelConfig = object["modelConfig"] as? [String: Any],
           let modelName = modelConfig["modelName"] as? String,
           !modelName.isEmpty {
            return modelName
        }
        return nil
    }

    private static func cursorComposerProjectPath(from object: [String: Any]) -> String? {
        let preferredCandidates: [Any?] = [
            object["workspaceIdentifier"],
            object["workspace"],
            object["projectPath"],
            object["cwd"],
            object["currentDirectory"],
            object["lastKnownWorkspacePath"]
        ]

        for candidate in preferredCandidates {
            if let path = cursorURIPath(from: candidate) {
                return path
            }
        }

        guard let context = object["context"] as? [String: Any] else { return nil }

        let candidateCollections: [Any?] = [
            context["fileSelections"],
            context["folderSelections"],
            context["selections"],
            context["attachedFolders"],
            context["attachedFoldersNew"]
        ]

        for collection in candidateCollections {
            guard let entries = collection as? [[String: Any]] else { continue }
            for entry in entries {
                if let path = cursorURIPath(from: entry["uri"]) {
                    return path
                }
                if let path = cursorURIPath(from: entry) {
                    return path
                }
            }
        }

        return nil
    }

    private static func cursorURIPath(from payload: Any?) -> String? {
        if let candidate = payload as? String {
            let normalized = normalizedProjectPath(candidate)
            if normalized?.isEmpty == false {
                return normalized
            }
        }

        guard let object = payload as? [String: Any] else { return nil }

        let candidateValues = [
            object["fsPath"] as? String,
            object["path"] as? String,
            object["external"] as? String
        ]

        for candidate in candidateValues {
            guard let candidate else { continue }
            let normalized = normalizedProjectPath(candidate)
            if normalized?.isEmpty == false {
                return normalized
            }
        }

        if let uri = object["uri"] as? [String: Any] {
            return cursorURIPath(from: uri)
        }

        return nil
    }

    private static func cursorComposerMetricsByUserBubbleID(
        db: OpaquePointer?,
        composerId: String,
        headers: [[String: Any]]
    ) -> [String: CursorBubbleMetrics] {
        var metricsByUserBubbleID: [String: CursorBubbleMetrics] = [:]
        var currentUserBubbleID: String?
        var currentBestMetrics: CursorBubbleMetrics?

        func flushCurrentMetrics() {
            guard let currentUserBubbleID, let currentBestMetrics else { return }
            metricsByUserBubbleID[currentUserBubbleID] = currentBestMetrics
        }

        for header in headers {
            guard let bubbleId = header["bubbleId"] as? String,
                  let type = header["type"] as? Int
            else {
                continue
            }

            if type == 1 {
                flushCurrentMetrics()
                currentUserBubbleID = bubbleId
                currentBestMetrics = nil
                continue
            }

            guard type == 2,
                  let metrics = fetchCursorBubbleMetrics(db: db, composerId: composerId, bubbleId: bubbleId)
            else {
                continue
            }

            currentBestMetrics = preferredCursorBubbleMetrics(currentBestMetrics, metrics)
        }

        flushCurrentMetrics()
        return metricsByUserBubbleID
    }

    private static func fetchCursorBubbleMetrics(db: OpaquePointer?, composerId: String, bubbleId: String) -> CursorBubbleMetrics? {
        let key = "bubbleId:\(composerId):\(bubbleId)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        let valueStr = String(cString: cString)
        guard let data = valueStr.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let usage: UsageTotals? = {
            guard let tokenCount = object["tokenCount"] as? [String: Any] else { return nil }
            let inputTokens = integerValue(tokenCount["inputTokens"]) ?? 0
            let outputTokens = integerValue(tokenCount["outputTokens"]) ?? 0
            guard inputTokens > 0 || outputTokens > 0 else { return nil }
            return UsageTotals(
                inputTokens: inputTokens,
                cachedInputTokens: 0,
                outputTokens: outputTokens,
                totalTokens: inputTokens + outputTokens
            )
        }()

        let responseTimeMs = cursorBubbleResponseTimeMs(from: object)
        guard usage != nil || responseTimeMs != nil else { return nil }
        return CursorBubbleMetrics(
            usage: usage,
            responseTimeMs: responseTimeMs
        )
    }

    private static func fetchCursorDiskKVText(db: OpaquePointer?, key: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else { return nil }
        let valueStr = String(cString: cString)
        guard let data = valueStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["text"] as? String
    }

    private static func parseCursorDatabase(_ url: URL, projectPath: String?) -> [ImportedPrompt] {
        guard let db = try? openSQLite(url) else {
            Self.runtimeLogger.error("Failed to open Cursor store", metadata: ["path": url.path])
            return []
        }
        defer { sqlite3_close(db) }

        let generationDates = cursorGenerationDates(db: db, key: "aiService.generations")
        let composerDates = cursorComposerDates(db: db, key: "composer.composerData")
        let promptAnchorDates = Array(Set(generationDates + composerDates)).sorted()
        let fallbackDate = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .now
        var imports: [ImportedPrompt] = []
        imports.append(contentsOf: decodeCursorPromptRows(db: db, key: "aiService.prompts", projectPath: projectPath, sourcePath: url.path, generationDates: promptAnchorDates, fallbackDate: fallbackDate))
        imports.append(contentsOf: decodeCursorGenerationRows(db: db, key: "aiService.generations", projectPath: projectPath, sourcePath: url.path))
        return imports
    }

    private static func decodeCursorPromptRows(db: OpaquePointer?, key: String, projectPath: String?, sourcePath: String, generationDates: [Date], fallbackDate: Date) -> [ImportedPrompt] {
        guard let value = fetchItemValue(db: db, key: key), let data = value.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.enumerated().compactMap { index, entry in
            guard let text = entry["text"] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { return nil }
            let capturedAt = cursorPromptTimestamp(promptIndex: index, promptCount: array.count, generationDates: generationDates, fallbackDate: fallbackDate)
            return ImportedPrompt(id: UUID().uuidString, provider: .cursor, title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Cursor Prompt"), body: trimmed, sourcePath: sourcePath, projectPath: projectPath, capturedAt: capturedAt, metadataOnly: false)
        }
    }

    private static func decodeCursorGenerationRows(db: OpaquePointer?, key: String, projectPath: String?, sourcePath: String) -> [ImportedPrompt] {
        guard let value = fetchItemValue(db: db, key: key), let data = value.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { entry in
            guard let text = entry["textDescription"] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { return nil }
            let timestamp = (entry["unixMs"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000.0) } ?? .now
            return ImportedPrompt(id: UUID().uuidString, provider: .cursor, title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Cursor Generation"), body: trimmed, sourcePath: sourcePath, projectPath: projectPath, capturedAt: timestamp, metadataOnly: false)
        }
    }

    private static func scanCopilot(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        let fileManager = FileManager.default
        let userRoots = copilotUserRoots(homeDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()))
        let copilotCLIRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".copilot/session-state", isDirectory: true)
        let copilotCommandHistoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".copilot/command-history-state.json", isDirectory: false)
        let hasCopilotCLI = fileManager.fileExists(atPath: copilotCLIRoot.path) || fileManager.fileExists(atPath: copilotCommandHistoryURL.path)
        guard !userRoots.isEmpty || hasCopilotCLI else {
            return ProviderScanResult(provider: .copilot)
        }

        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        for userRoot in userRoots {
            let globalSessionsRoot = userRoot.appendingPathComponent("globalStorage/emptyWindowChatSessions", isDirectory: true)
            if fileManager.fileExists(atPath: globalSessionsRoot.path) {
                let globalSessions = (try? fileManager.contentsOfDirectory(at: globalSessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                let result = scanFiles(provider: .copilot, files: globalSessions.filter(isSupportedCopilotSessionFile(_:)), cache: cache) { fileURL in
                    parseCopilotSession(fileURL, projectPath: nil)
                }
                prompts += result.prompts
                cacheEntries.merge(result.cacheEntries, uniquingKeysWith: { _, new in new })
                cacheHits += result.cacheHits
                parsedCount += result.parsedCount
            }

            let workspaceStorageRoot = userRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
            if fileManager.fileExists(atPath: workspaceStorageRoot.path) {
                let workspaceDirs = (try? fileManager.contentsOfDirectory(at: workspaceStorageRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for dir in workspaceDirs {
                    let sessionsRoot = dir.appendingPathComponent("chatSessions", isDirectory: true)
                    let workspaceJSON = dir.appendingPathComponent("workspace.json")
                    let projectPath = parseWorkspacePath(workspaceJSON)
                    var knownPromptTexts = Set<String>()

                    var earliestKnownSessionPromptAt: Date?

                    if fileManager.fileExists(atPath: sessionsRoot.path) {
                        let sessionFiles = (try? fileManager.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                        let result = scanFiles(provider: .copilot, files: sessionFiles.filter(isSupportedCopilotSessionFile(_:)), cache: cache) { fileURL in
                            parseCopilotSession(fileURL, projectPath: projectPath)
                        }
                        prompts += result.prompts
                        cacheEntries.merge(result.cacheEntries, uniquingKeysWith: { _, new in new })
                        cacheHits += result.cacheHits
                        parsedCount += result.parsedCount
                        knownPromptTexts.formUnion(result.prompts.map(\.body))
                        earliestKnownSessionPromptAt = result.prompts.map(\.capturedAt).min()
                    }

                    let stateDBURL = dir.appendingPathComponent("state.vscdb")
                    if fileManager.fileExists(atPath: stateDBURL.path) {
                        let result = scanFiles(provider: .copilot, files: [stateDBURL], cache: cache) { fileURL in
                            parseCopilotWorkspaceState(
                                fileURL,
                                projectPath: projectPath,
                                excludingBodies: knownPromptTexts,
                                anchorBefore: earliestKnownSessionPromptAt
                            )
                        }
                        prompts += result.prompts
                        cacheEntries.merge(result.cacheEntries, uniquingKeysWith: { _, new in new })
                        cacheHits += result.cacheHits
                        parsedCount += result.parsedCount
                    }
                }
            }
        }

        if hasCopilotCLI {
            if fileManager.fileExists(atPath: copilotCLIRoot.path) {
                let cliResult = scanCopilotCLISessions(root: copilotCLIRoot, cache: cache)
                prompts += cliResult.prompts
                cacheEntries.merge(cliResult.cacheEntries, uniquingKeysWith: { _, new in new })
                cacheHits += cliResult.cacheHits
                parsedCount += cliResult.parsedCount
            }

            if fileManager.fileExists(atPath: copilotCommandHistoryURL.path) {
                let historyResult = scanFiles(provider: .copilot, files: [copilotCommandHistoryURL], cache: cache, parser: parseCopilotCommandHistory)
                prompts = mergeCopilotCommandHistoryPrompts(primary: prompts, history: historyResult.prompts)
                cacheEntries.merge(historyResult.cacheEntries, uniquingKeysWith: { _, new in new })
                cacheHits += historyResult.cacheHits
                parsedCount += historyResult.parsedCount
            }
        }

        return ProviderScanResult(provider: .copilot, prompts: prompts, cacheEntries: cacheEntries, cacheHits: cacheHits, parsedCount: parsedCount)
    }

    static func scanCopilotPromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        let fileManager = FileManager.default
        var prompts: [ImportedPrompt] = []

        for userRoot in copilotUserRoots(homeDirectoryURL: homeDirectoryURL) {
            let globalSessionsRoot = userRoot.appendingPathComponent("globalStorage/emptyWindowChatSessions", isDirectory: true)
            if fileManager.fileExists(atPath: globalSessionsRoot.path) {
                let globalSessions = (try? fileManager.contentsOfDirectory(at: globalSessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for fileURL in globalSessions where isSupportedCopilotSessionFile(fileURL) {
                    prompts += parseCopilotSession(fileURL, projectPath: nil)
                }
            }

            let workspaceStorageRoot = userRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
            if fileManager.fileExists(atPath: workspaceStorageRoot.path) {
                let workspaceDirs = (try? fileManager.contentsOfDirectory(at: workspaceStorageRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for dir in workspaceDirs {
                    let sessionsRoot = dir.appendingPathComponent("chatSessions", isDirectory: true)
                    let workspaceJSON = dir.appendingPathComponent("workspace.json")
                    let projectPath = parseWorkspacePath(workspaceJSON)
                    var knownPromptTexts = Set<String>()

                    var earliestKnownSessionPromptAt: Date?

                    if fileManager.fileExists(atPath: sessionsRoot.path) {
                        let sessionFiles = (try? fileManager.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                        for fileURL in sessionFiles where isSupportedCopilotSessionFile(fileURL) {
                            let parsed = parseCopilotSession(fileURL, projectPath: projectPath)
                            prompts += parsed
                            knownPromptTexts.formUnion(parsed.map(\.body))
                            let earliestParsedAt = parsed.map(\.capturedAt).min()
                            if let earliestParsedAt {
                                earliestKnownSessionPromptAt = min(earliestKnownSessionPromptAt ?? earliestParsedAt, earliestParsedAt)
                            }
                        }
                    }

                    let stateDBURL = dir.appendingPathComponent("state.vscdb")
                    if fileManager.fileExists(atPath: stateDBURL.path) {
                        prompts += parseCopilotWorkspaceState(
                            stateDBURL,
                            projectPath: projectPath,
                            excludingBodies: knownPromptTexts,
                            anchorBefore: earliestKnownSessionPromptAt
                        )
                    }
                }
            }
        }

        let copilotCLIRoot = homeDirectoryURL.appendingPathComponent(".copilot/session-state", isDirectory: true)
        if fileManager.fileExists(atPath: copilotCLIRoot.path) {
            prompts += scanCopilotCLISessionsForTesting(root: copilotCLIRoot)
        }

        let copilotCommandHistoryURL = homeDirectoryURL.appendingPathComponent(".copilot/command-history-state.json", isDirectory: false)
        if fileManager.fileExists(atPath: copilotCommandHistoryURL.path) {
            prompts = mergeCopilotCommandHistoryPrompts(primary: prompts, history: parseCopilotCommandHistory(copilotCommandHistoryURL))
        }

        return prompts.sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func scanCopilotCLISessions(
        root: URL,
        cache: [String: IntegrationScanCacheStore.Entry]
    ) -> ProviderScanResult {
        let fileManager = FileManager.default
        let sessionDirs = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        for dir in sessionDirs {
            let eventsURL = dir.appendingPathComponent("events.jsonl", isDirectory: false)
            guard fileManager.fileExists(atPath: eventsURL.path) else { continue }

            let workspaceURL = dir.appendingPathComponent("workspace.yaml", isDirectory: false)
            let sessionInfo = parseCopilotCLIWorkspace(workspaceURL)
            let cacheKey = sourceCacheKey(provider: .copilot, sourcePath: eventsURL.path)
            let fingerprint = compositeFingerprint(for: [eventsURL, workspaceURL])

            if let fingerprint,
               let cached = cache[cacheKey],
               cached.fingerprint == fingerprint {
                prompts.append(contentsOf: cached.prompts)
                cacheEntries[cacheKey] = cached
                cacheHits += 1
                continue
            }

            let parsed = parseCopilotCLISession(eventsURL, projectPath: sessionInfo.projectPath, sourceContextID: sessionInfo.contextID)
            prompts.append(contentsOf: parsed)
            if let fingerprint {
                cacheEntries[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
            }
            parsedCount += 1
        }

        return ProviderScanResult(provider: .copilot, prompts: prompts, cacheEntries: cacheEntries, cacheHits: cacheHits, parsedCount: parsedCount)
    }

    private static func scanCopilotCLISessionsForTesting(root: URL) -> [ImportedPrompt] {
        let fileManager = FileManager.default
        let sessionDirs = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var prompts: [ImportedPrompt] = []

        for dir in sessionDirs {
            let eventsURL = dir.appendingPathComponent("events.jsonl", isDirectory: false)
            guard fileManager.fileExists(atPath: eventsURL.path) else { continue }
            let workspaceURL = dir.appendingPathComponent("workspace.yaml", isDirectory: false)
            let sessionInfo = parseCopilotCLIWorkspace(workspaceURL)
            prompts += parseCopilotCLISession(eventsURL, projectPath: sessionInfo.projectPath, sourceContextID: sessionInfo.contextID)
        }

        return prompts
    }

    static func parseCopilotSession(_ url: URL, projectPath: String?) -> [ImportedPrompt] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let sessionObjects = decodeCopilotSessionObjects(from: raw)
        var seenRequestIDs = Set<String>()
        var imports: [ImportedPrompt] = []
        let fileModifiedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .now

        for session in sessionObjects {
            let requests = copilotRequests(from: session)
            guard !requests.isEmpty else { continue }
            let fallbackDate = copilotFallbackDate(from: session) ?? fileModifiedAt

            for request in requests {
                if let requestID = request["requestId"] as? String, !seenRequestIDs.insert(requestID).inserted {
                    continue
                }
                guard let text = copilotRequestText(from: request) else { continue }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { continue }
                let timestamp = (request["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000.0) } ?? fallbackDate
                let modelID = normalizedCopilotModelID(from: request, session: session)
                let estimatedInputTokens = estimateTokenCount(from: copilotRenderedInputText(from: request) ?? trimmed)
                let estimatedOutputTokens = copilotResponseText(from: request).flatMap(estimateTokenCount(from:))
                imports.append(
                    ImportedPrompt(
                        id: UUID().uuidString,
                        provider: .copilot,
                        title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Copilot Prompt"),
                        body: trimmed,
                        sourcePath: url.path,
                        projectPath: projectPath,
                        capturedAt: timestamp,
                        metadataOnly: false,
                        sourceContextID: url.path,
                        modelID: modelID,
                        inputTokens: estimatedInputTokens,
                        cachedInputTokens: nil,
                        outputTokens: estimatedOutputTokens,
                        totalTokens: {
                            guard let estimatedInputTokens, let estimatedOutputTokens else { return nil }
                            return estimatedInputTokens + estimatedOutputTokens
                        }()
                    )
                )
            }
        }

        return imports
    }

    private static func parseCopilotCLISession(_ url: URL, projectPath: String?, sourceContextID: String?) -> [ImportedPrompt] {
        let fileModifiedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .now
        var imports: [ImportedPrompt] = []
        var currentModelID: String?
        var fallbackProjectPath = projectPath
        var promptIndexByInteractionID: [String: Int] = [:]
        var outputTokensByInteractionID: [String: Int] = [:]

        forEachJSONObjectLine(in: url) { object in
            guard let type = object["type"] as? String,
                  let eventData = object["data"] as? [String: Any]
            else { return }

            switch type {
            case "session.start":
                if fallbackProjectPath == nil,
                   let context = eventData["context"] as? [String: Any],
                   let cwd = context["cwd"] as? String {
                    fallbackProjectPath = normalizedProjectPath(cwd)
                }
            case "session.model_change":
                if let newModel = eventData["newModel"] as? String, !newModel.isEmpty {
                    currentModelID = stripCopilotModelPrefix(newModel)
                }
            case "user.message":
                let bodyText = ((eventData["content"] as? String) ?? (eventData["transformedContent"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bodyText.isEmpty, isLikelyUserPrompt(bodyText) else { return }
                let inputEstimateText = ((eventData["transformedContent"] as? String) ?? (eventData["content"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let timestamp = (object["timestamp"] as? String).flatMap(DateFormatting.parse) ?? fileModifiedAt
                imports.append(
                    ImportedPrompt(
                        id: UUID().uuidString,
                        provider: .copilot,
                        title: cleanPromptTitle(bodyText.components(separatedBy: .newlines).first ?? "Copilot Prompt"),
                        body: bodyText,
                        sourcePath: url.path,
                        projectPath: fallbackProjectPath,
                        capturedAt: timestamp,
                        metadataOnly: false,
                        sourceContextID: sourceContextID ?? url.deletingLastPathComponent().lastPathComponent,
                        modelID: currentModelID,
                        inputTokens: estimateTokenCount(from: inputEstimateText),
                        cachedInputTokens: nil,
                        outputTokens: nil,
                        totalTokens: nil
                    )
                )
                if let interactionID = eventData["interactionId"] as? String, !interactionID.isEmpty,
                   let promptIndex = imports.indices.last {
                    promptIndexByInteractionID[interactionID] = promptIndex
                }
            case "assistant.message":
                guard let interactionID = eventData["interactionId"] as? String,
                      let promptIndex = promptIndexByInteractionID[interactionID]
                else { return }
                if let modelID = eventData["model"] as? String, !modelID.isEmpty {
                    imports[promptIndex].modelID = stripCopilotModelPrefix(modelID)
                }
                if let outputTokens = integerValue(eventData["outputTokens"]), outputTokens > 0 {
                    let preferredOutputTokens = max(outputTokensByInteractionID[interactionID] ?? 0, outputTokens)
                    outputTokensByInteractionID[interactionID] = preferredOutputTokens
                    imports[promptIndex].outputTokens = preferredOutputTokens
                    let inputTokens = imports[promptIndex].inputTokens ?? 0
                    imports[promptIndex].totalTokens = inputTokens + preferredOutputTokens
                }
            case "tool.execution_complete":
                guard let interactionID = eventData["interactionId"] as? String,
                      let promptIndex = promptIndexByInteractionID[interactionID]
                else { return }
                if let modelID = eventData["model"] as? String, !modelID.isEmpty {
                    imports[promptIndex].modelID = stripCopilotModelPrefix(modelID)
                }
            default:
                break
            }
        }

        return imports
    }

    private static func parseCopilotCommandHistory(_ url: URL) -> [ImportedPrompt] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let history = object["commandHistory"] as? [String],
              !history.isEmpty
        else {
            return []
        }

        let fileModifiedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .now

        return history.enumerated().compactMap { index, entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { return nil }

            let offset = history.count - index
            let capturedAt = fileModifiedAt.addingTimeInterval(TimeInterval(-offset))
            return ImportedPrompt(
                id: UUID().uuidString,
                provider: .copilot,
                title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Copilot Prompt"),
                body: trimmed,
                sourcePath: url.path,
                projectPath: nil,
                capturedAt: capturedAt,
                metadataOnly: false,
                inputTokens: estimateTokenCount(from: trimmed),
                cachedInputTokens: nil,
                outputTokens: nil,
                totalTokens: nil
            )
        }
    }

    private static func decodeCopilotSessionObjects(from raw: String) -> [[String: Any]] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let wrapped = object["v"] as? [String: Any] {
                return [wrapped]
            }
            return [object]
        }

        return trimmed
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    return nil
                }
                if let wrapped = object["v"] as? [String: Any] {
                    return wrapped
                }
                return object
            }
    }

    private static func copilotRequests(from object: [String: Any]) -> [[String: Any]] {
        if let requests = object["requests"] as? [[String: Any]] {
            return requests
        }

        if let wrapped = object["v"] as? [String: Any],
           let requests = wrapped["requests"] as? [[String: Any]] {
            return requests
        }

        if let kind = object["kind"] as? NSNumber,
           kind.intValue == 2,
           let keyPath = object["k"] as? [String],
           keyPath == ["requests"],
           let requests = object["v"] as? [[String: Any]] {
            return requests
        }

        return []
    }

    private static func copilotFallbackDate(from object: [String: Any]) -> Date? {
        if let lastMessageDate = object["lastMessageDate"] as? NSNumber {
            return Date(timeIntervalSince1970: lastMessageDate.doubleValue / 1000.0)
        }

        if let creationDate = object["creationDate"] as? NSNumber {
            return Date(timeIntervalSince1970: creationDate.doubleValue / 1000.0)
        }

        if let wrapped = object["v"] as? [String: Any] {
            return copilotFallbackDate(from: wrapped)
        }

        return nil
    }

    private static func copilotRequestText(from request: [String: Any]) -> String? {
        if let message = request["message"] as? [String: Any],
           let text = message["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        if let result = request["result"] as? [String: Any],
           let metadata = result["metadata"] as? [String: Any],
           let renderedUserMessage = metadata["renderedUserMessage"] as? [[String: Any]] {
            let combined = renderedUserMessage.compactMap { item in
                item["text"] as? String
            }.joined()
            if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return combined
            }
        }

        return nil
    }

    private static func copilotRenderedInputText(from request: [String: Any]) -> String? {
        let primary = copilotRequestText(from: request)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rendered = copilotRenderedUserMessageText(from: request)?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (primary, rendered) {
        case let (primary?, rendered?) where rendered != primary:
            return "\(primary)\n\(rendered)"
        case let (primary?, _):
            return primary
        case let (_, rendered?):
            return rendered
        default:
            return nil
        }
    }

    private static func copilotRenderedUserMessageText(from request: [String: Any]) -> String? {
        guard let result = request["result"] as? [String: Any],
              let metadata = result["metadata"] as? [String: Any],
              let renderedUserMessage = metadata["renderedUserMessage"] as? [[String: Any]]
        else {
            return nil
        }

        let combined = renderedUserMessage.compactMap { item in
            item["text"] as? String
        }.joined()

        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func copilotResponseText(from request: [String: Any]) -> String? {
        guard let response = request["response"] as? [[String: Any]], !response.isEmpty else {
            return nil
        }

        let parts = response.compactMap { responsePart -> String? in
            let kind = (responsePart["kind"] as? String)?.lowercased()
            if let kind, ["progressmessage", "thinking", "mcpserversstarting", "command", "warning"].contains(kind) {
                return nil
            }

            if let value = responsePart["value"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            if let content = responsePart["content"] as? [String: Any],
               let value = content["value"] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            return nil
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private static func normalizedCopilotModelID(from request: [String: Any], session: [String: Any]) -> String? {
        if let modelID = request["modelId"] as? String {
            return stripCopilotModelPrefix(modelID)
        }

        if let inputState = session["inputState"] as? [String: Any],
           let selectedModel = inputState["selectedModel"] as? [String: Any] {
            if let identifier = selectedModel["identifier"] as? String {
                return stripCopilotModelPrefix(identifier)
            }
            if let metadata = selectedModel["metadata"] as? [String: Any] {
                if let version = metadata["version"] as? String, !version.isEmpty {
                    return stripCopilotModelPrefix(version)
                }
                if let family = metadata["family"] as? String, !family.isEmpty {
                    return stripCopilotModelPrefix(family)
                }
                if let id = metadata["id"] as? String, !id.isEmpty {
                    return stripCopilotModelPrefix(id)
                }
            }
        }

        return nil
    }

    private static func stripCopilotModelPrefix(_ modelID: String) -> String {
        let prefix = "copilot/"
        if modelID.hasPrefix(prefix) {
            return String(modelID.dropFirst(prefix.count))
        }
        return modelID
    }

    private static func parseCopilotCLIWorkspace(_ url: URL) -> (projectPath: String?, contextID: String?) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }

        var values: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  let colonIndex = trimmed.firstIndex(of: ":")
            else {
                continue
            }

            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: colonIndex)
            let value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        return (
            normalizedProjectPath(values["cwd"]),
            values["id"]
        )
    }

    private static func parseCopilotWorkspaceState(
        _ url: URL,
        projectPath: String?,
        excludingBodies: Set<String>,
        anchorBefore: Date? = nil
    ) -> [ImportedPrompt] {
        guard let db = try? openSQLite(url) else { return [] }
        defer { sqlite3_close(db) }

        guard let raw = fetchItemValue(db: db, key: "memento/interactive-session"),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let history = object["history"] as? [String: Any]
        let entries = history?["copilot"] as? [[String: Any]] ?? []
        guard !entries.isEmpty else { return [] }

        let fileModifiedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .now
        let fallbackBaseDate: Date = {
            guard let anchorBefore else { return fileModifiedAt }
            return anchorBefore.addingTimeInterval(TimeInterval(-(entries.count + 1)))
        }()
        var imports: [ImportedPrompt] = []
        var seenBodies = excludingBodies

        for (index, entry) in entries.enumerated() {
            guard let text = entry["inputText"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isLikelyUserPrompt(trimmed) else { continue }
            guard seenBodies.insert(trimmed).inserted else { continue }

            let capturedAt: Date = {
                guard anchorBefore != nil else {
                    let offset = entries.count - index
                    return fileModifiedAt.addingTimeInterval(TimeInterval(-offset))
                }
                return fallbackBaseDate.addingTimeInterval(TimeInterval(index))
            }()
            let modelID = normalizedCopilotModelID(fromWorkspaceHistoryEntry: entry)
            let estimatedInputTokens = estimateTokenCount(from: trimmed)
            imports.append(
                ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .copilot,
                    title: cleanPromptTitle(trimmed.components(separatedBy: .newlines).first ?? "Copilot Prompt"),
                    body: trimmed,
                    sourcePath: url.path,
                    projectPath: projectPath,
                    capturedAt: capturedAt,
                    metadataOnly: false,
                    sourceContextID: url.path,
                    modelID: modelID,
                    inputTokens: estimatedInputTokens,
                    cachedInputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil
                )
            )
        }

        return imports
    }

    private static func normalizedCopilotModelID(fromWorkspaceHistoryEntry entry: [String: Any]) -> String? {
        guard let selectedModel = entry["selectedModel"] as? [String: Any] else { return nil }
        if let identifier = selectedModel["identifier"] as? String, !identifier.isEmpty {
            return stripCopilotModelPrefix(identifier)
        }
        if let metadata = selectedModel["metadata"] as? [String: Any] {
            if let version = metadata["version"] as? String, !version.isEmpty {
                return stripCopilotModelPrefix(version)
            }
            if let family = metadata["family"] as? String, !family.isEmpty {
                return stripCopilotModelPrefix(family)
            }
            if let id = metadata["id"] as? String, !id.isEmpty {
                return stripCopilotModelPrefix(id)
            }
        }
        return nil
    }

    private static func isSupportedCopilotSessionFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "json" || ext == "jsonl"
    }

    private static func scanOpenCode(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        scanOpenCode(homeDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()), cache: cache)
    }

    private static func scanOpenCode(
        homeDirectoryURL: URL,
        cache: [String: IntegrationScanCacheStore.Entry]
    ) -> ProviderScanResult {
        let fileManager = FileManager.default
        let root = homeDirectoryURL.appendingPathComponent("Library/Application Support/ai.opencode.desktop", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else {
            return ProviderScanResult(provider: .opencode)
        }

        let sessionMap = openCodeSessionMap(globalStoreURL: root.appendingPathComponent("opencode.global.dat"))
        var files: [URL] = []
        let globalURL = root.appendingPathComponent("opencode.global.dat")
        if fileManager.fileExists(atPath: globalURL.path) {
            files.append(globalURL)
        }

        let candidates = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in candidates where url.lastPathComponent.hasPrefix("opencode.workspace") && url.pathExtension == "dat" {
            files.append(url)
        }

        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        for fileURL in files {
            let cacheKey = sourceCacheKey(provider: .opencode, sourcePath: fileURL.path)
            let fingerprint = fileFingerprint(for: fileURL)
            if let fingerprint,
               let cached = cache[cacheKey],
               cached.fingerprint == fingerprint {
                prompts.append(contentsOf: cached.prompts)
                cacheEntries[cacheKey] = cached
                cacheHits += 1
                continue
            }

            let cachedPrompts = cache[cacheKey]?.prompts ?? []
            let parsed = autoreleasepool {
                parseOpenCodeStoreFile(
                    fileURL,
                    sessionProjectMap: sessionMap,
                    cachedPrompts: cachedPrompts
                )
            }
            prompts.append(contentsOf: parsed)
            if let fingerprint {
                cacheEntries[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
            }
            parsedCount += 1
        }

        return ProviderScanResult(
            provider: .opencode,
            prompts: prompts,
            cacheEntries: cacheEntries,
            cacheHits: cacheHits,
            parsedCount: parsedCount
        )
    }

    static func scanOpenCodePromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        scanOpenCode(homeDirectoryURL: homeDirectoryURL, cache: [:]).prompts
    }

    /// Maps OpenCode session ids (e.g. `ses_…`) to project directories from `layout.page`.
    private static func openCodeSessionMap(globalStoreURL: URL) -> [String: OpenCodeSessionMetadata] {
        guard FileManager.default.fileExists(atPath: globalStoreURL.path),
              let data = try? Data(contentsOf: globalStoreURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layoutJSON = root["layout.page"] as? String,
              let layoutData = layoutJSON.data(using: .utf8),
              let layout = try? JSONSerialization.jsonObject(with: layoutData) as? [String: Any],
              let last = layout["lastProjectSession"] as? [String: Any]
        else {
            return [:]
        }

        var map: [String: OpenCodeSessionMetadata] = [:]
        for (_, value) in last {
            guard let obj = value as? [String: Any],
                  let id = obj["id"] as? String,
                  let directory = obj["directory"] as? String
            else {
                continue
            }
            map[id] = OpenCodeSessionMetadata(
                directory: normalizedProjectPath(directory) ?? directory,
                lastActivityAt: openCodeTimestampDate(obj["at"])
            )
        }
        return map
    }

    private static func parseOpenCodeStoreFile(
        _ url: URL,
        sessionProjectMap: [String: OpenCodeSessionMetadata],
        cachedPrompts: [ImportedPrompt]
    ) -> [ImportedPrompt] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileModifiedAt = (fileAttributes?[.modificationDate] as? Date) ?? .now
        let fileCreatedAt = fileAttributes?[.creationDate] as? Date
        var seenBodies = Set<String>()
        var imports: [ImportedPrompt] = []
        let cachedDates = openCodeCachedDateMap(from: cachedPrompts)
        let hasCachedHistoryDates = cachedDates.keys.contains { $0.contextID == url.path }

        if let historyRaw = obj["prompt-history"] as? String {
            imports.append(contentsOf: openCodePromptsFromPromptHistoryJSON(
                historyRaw,
                sourcePath: url.path,
                fallbackAnchorDate: hasCachedHistoryDates ? fileModifiedAt : (fileCreatedAt ?? fileModifiedAt),
                preferRecentAnchor: hasCachedHistoryDates,
                cachedDates: cachedDates,
                seenBodies: &seenBodies
            ))
        }

        let promptKeys = obj.keys.filter { key in
            key == "workspace:prompt" || (key.hasPrefix("session:") && key.hasSuffix(":prompt"))
        }.sorted()

        for (index, key) in promptKeys.enumerated() {
            guard let jsonPayload = obj[key] as? String,
                  let text = openCodeUserPromptText(fromJSONPayload: jsonPayload),
                  isLikelyUserPrompt(text),
                  seenBodies.insert(text).inserted
            else {
                continue
            }

            let projectPath: String? = {
                if key == "workspace:prompt" {
                    return nil
                }
                guard let sid = openCodeSessionId(promptStorageKey: key) else {
                    return nil
                }
                return sessionProjectMap[sid]?.directory
            }()

            let contextID = openCodeSessionId(promptStorageKey: key) ?? key
            let offset = promptKeys.count - index
            let fallbackAnchorDate = openCodeSessionId(promptStorageKey: key)
                .flatMap { sessionProjectMap[$0]?.lastActivityAt }
                ?? fileModifiedAt
            let capturedAt = openCodeResolvedCapturedAt(
                text: text,
                contextID: contextID,
                cachedDates: cachedDates,
                fallbackDate: fallbackAnchorDate.addingTimeInterval(TimeInterval(-offset))
            )
            imports.append(
                ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .opencode,
                    title: cleanPromptTitle(text.components(separatedBy: .newlines).first ?? "OpenCode Prompt"),
                    body: text,
                    sourcePath: url.path,
                    projectPath: projectPath,
                    capturedAt: capturedAt,
                    metadataOnly: false,
                    sourceContextID: contextID
                )
            )
        }

        return imports
    }

    static func parseOpenCodeStoreFileForTesting(
        _ url: URL,
        sessionProjectMap: [String: (directory: String, lastActivityAt: Date?)] = [:],
        cachedPrompts: [ImportedPrompt] = []
    ) -> [ImportedPrompt] {
        parseOpenCodeStoreFile(
            url,
            sessionProjectMap: sessionProjectMap.mapValues { value in
                OpenCodeSessionMetadata(
                    directory: value.directory,
                    lastActivityAt: value.lastActivityAt
                )
            },
            cachedPrompts: cachedPrompts
        )
    }

    private static func openCodePromptsFromPromptHistoryJSON(
        _ json: String,
        sourcePath: String,
        fallbackAnchorDate: Date,
        preferRecentAnchor: Bool,
        cachedDates: [OpenCodeCachedPromptKey: Date],
        seenBodies: inout Set<String>
    ) -> [ImportedPrompt] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [Any],
              !entries.isEmpty
        else {
            return []
        }

        var imports: [ImportedPrompt] = []
        for (index, entry) in entries.enumerated() {
            guard let text = openCodePromptText(fromHistoryEntry: entry),
                  isLikelyUserPrompt(text),
                  seenBodies.insert(text).inserted
            else {
                continue
            }
            let offset = entries.count - index
            let fallbackDate: Date
            if preferRecentAnchor {
                fallbackDate = fallbackAnchorDate.addingTimeInterval(TimeInterval(-offset))
            } else {
                fallbackDate = fallbackAnchorDate.addingTimeInterval(TimeInterval(index))
            }
            let capturedAt = openCodeResolvedCapturedAt(
                text: text,
                contextID: sourcePath,
                cachedDates: cachedDates,
                fallbackDate: fallbackDate
            )
            imports.append(
                ImportedPrompt(
                    id: UUID().uuidString,
                    provider: .opencode,
                    title: cleanPromptTitle(text.components(separatedBy: .newlines).first ?? "OpenCode Prompt"),
                    body: text,
                    sourcePath: sourcePath,
                    projectPath: nil,
                    capturedAt: capturedAt,
                    metadataOnly: false,
                    sourceContextID: sourcePath
                )
            )
        }
        return imports
    }

    private static func openCodeCachedDateMap(from prompts: [ImportedPrompt]) -> [OpenCodeCachedPromptKey: Date] {
        prompts.reduce(into: [OpenCodeCachedPromptKey: Date]()) { partialResult, prompt in
            guard let contextID = prompt.sourceContextID else { return }
            partialResult[OpenCodeCachedPromptKey(contextID: contextID, text: prompt.body)] = prompt.capturedAt
        }
    }

    private static func openCodeResolvedCapturedAt(
        text: String,
        contextID: String,
        cachedDates: [OpenCodeCachedPromptKey: Date],
        fallbackDate: Date
    ) -> Date {
        cachedDates[OpenCodeCachedPromptKey(contextID: contextID, text: text)] ?? fallbackDate
    }

    private static func openCodeTimestampDate(_ rawValue: Any?) -> Date? {
        guard let milliseconds = rawValue as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
    }

    private static func openCodePromptText(fromHistoryEntry entry: Any) -> String? {
        if let dict = entry as? [String: Any],
           let blocks = dict["prompt"] as? [[String: Any]] {
            return openCodeJoinedTextBlocks(blocks)
        }
        if let blocks = entry as? [[String: Any]] {
            return openCodeJoinedTextBlocks(blocks)
        }
        return nil
    }

    private static func openCodeUserPromptText(fromJSONPayload jsonPayload: String) -> String? {
        guard let data = jsonPayload.data(using: .utf8) else { return nil }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let blocks = root["prompt"] as? [[String: Any]] {
            return openCodeJoinedTextBlocks(blocks)
        }
        if let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return openCodeJoinedTextBlocks(blocks)
        }
        return nil
    }

    private static func openCodeJoinedTextBlocks(_ blocks: [[String: Any]]) -> String? {
        let parts = blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["content"] as? String
        }
        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func openCodeSessionId(promptStorageKey key: String) -> String? {
        let prefix = "session:"
        let suffix = ":prompt"
        guard key.hasPrefix(prefix), key.hasSuffix(suffix), key.count > prefix.count + suffix.count else {
            return nil
        }
        return String(key.dropFirst(prefix.count).dropLast(suffix.count))
    }

    /// Imports Antigravity **agent task** text from `~/.gemini/antigravity/brain/<id>/` (metadata summary + optional `task.md`).
    /// Raw chat transcripts live in encrypted `conversations/*.pb` and are not parsed here.
    private static func scanAntigravityBrainTasks(cache: [String: IntegrationScanCacheStore.Entry]) -> ProviderScanResult {
        scanAntigravityBrainTasks(homeDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()), cache: cache)
    }

    private static func scanAntigravityBrainTasks(
        homeDirectoryURL: URL,
        cache: [String: IntegrationScanCacheStore.Entry]
    ) -> ProviderScanResult {
        let fileManager = FileManager.default
        let root = homeDirectoryURL.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else {
            return ProviderScanResult(provider: .antigravity)
        }

        let sessionDirs = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let metadataFiles: [URL] = sessionDirs.compactMap { dir in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let meta = dir.appendingPathComponent("task.md.metadata.json", isDirectory: false)
            guard fileManager.fileExists(atPath: meta.path) else { return nil }
            return meta
        }

        return scanFiles(provider: .antigravity, files: metadataFiles, cache: cache, parser: parseAntigravityTaskMetadataFile)
    }

    static func scanAntigravityPromptsForTesting(homeDirectoryURL: URL) -> [ImportedPrompt] {
        scanAntigravityBrainTasks(homeDirectoryURL: homeDirectoryURL, cache: [:]).prompts
    }

    private static func parseAntigravityTaskMetadataFile(_ metadataURL: URL) -> [ImportedPrompt] {
        guard let data = try? Data(contentsOf: metadataURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = obj["summary"] as? String
        else {
            return []
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return [] }

        let parentDir = metadataURL.deletingLastPathComponent()
        let taskURL = parentDir.appendingPathComponent("task.md", isDirectory: false)
        var body = trimmedSummary
        if let taskRaw = try? String(contentsOf: taskURL, encoding: .utf8) {
            let taskTrim = taskRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !taskTrim.isEmpty, taskTrim != trimmedSummary {
                body = "\(trimmedSummary)\n\n\(taskTrim)"
            }
        }

        let bodyTrimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyUserPrompt(bodyTrimmed) else { return [] }

        let capturedAt = antigravityMetadataDate(obj["updatedAt"]) ?? (((try? FileManager.default.attributesOfItem(atPath: metadataURL.path)[.modificationDate]) as? Date) ?? .now)

        let modelID = (obj["model"] as? String) ?? "gemini"

        return [
            ImportedPrompt(
                id: UUID().uuidString,
                provider: .antigravity,
                title: cleanPromptTitle(trimmedSummary.components(separatedBy: .newlines).first ?? "Antigravity Task"),
                body: bodyTrimmed,
                sourcePath: metadataURL.path,
                projectPath: nil,
                capturedAt: capturedAt,
                metadataOnly: false,
                tags: ["antigravity-brain"],
                modelID: modelID
            )
        ]
    }

    private static func antigravityMetadataDate(_ value: Any?) -> Date? {
        guard let str = value as? String, !str.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: str) {
            return d
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: str)
    }

    private static func estimateTokenCount(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let scalarCount = trimmed.unicodeScalars.count
        guard scalarCount > 0 else { return nil }
        return max(1, Int(ceil(Double(scalarCount) / 4.0)))
    }

    private static func scanFiles(
        provider: IntegrationProvider,
        files: [URL],
        cache: [String: IntegrationScanCacheStore.Entry],
        parser: (URL) -> [ImportedPrompt]
    ) -> ProviderScanResult {
        var prompts: [ImportedPrompt] = []
        var cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:]
        var cacheHits = 0
        var parsedCount = 0

        for fileURL in files {
            let cacheKey = sourceCacheKey(provider: provider, sourcePath: fileURL.path)
            let fingerprint = fileFingerprint(for: fileURL)
            if let fingerprint,
               let cached = cache[cacheKey],
               cached.fingerprint == fingerprint {
                prompts.append(contentsOf: cached.prompts)
                cacheEntries[cacheKey] = cached
                cacheHits += 1
                continue
            }

            let parsed = autoreleasepool {
                parser(fileURL)
            }
            prompts.append(contentsOf: parsed)
            if let fingerprint {
                cacheEntries[cacheKey] = IntegrationScanCacheStore.Entry(fingerprint: fingerprint, prompts: parsed)
            }
            parsedCount += 1
        }

        return ProviderScanResult(
            provider: provider,
            prompts: prompts,
            cacheEntries: cacheEntries,
            cacheHits: cacheHits,
            parsedCount: parsedCount
        )
    }

    static func sourceCacheKey(provider: IntegrationProvider, sourcePath: String) -> String {
        "v\(parserVersion):\(provider.rawValue):\(sourcePath)"
    }

    private static func usageTotals(from payload: Any?) -> UsageTotals? {
        guard let payload = payload as? [String: Any] else { return nil }
        let inputTokens = integerValue(payload["input_tokens"])
        let cachedInputTokens = integerValue(payload["cached_input_tokens"])
        let outputTokens = integerValue(payload["output_tokens"])
        let totalTokens = integerValue(payload["total_tokens"])
        guard inputTokens != nil || outputTokens != nil || totalTokens != nil else { return nil }
        return UsageTotals(
            inputTokens: inputTokens ?? 0,
            cachedInputTokens: cachedInputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            totalTokens: totalTokens ?? max(0, (inputTokens ?? 0) + (outputTokens ?? 0))
        )
    }

    private static func usageTotals(fromClaudeUsage payload: Any?) -> UsageTotals? {
        guard let payload = payload as? [String: Any] else { return nil }

        let inputTokens = integerValue(payload["input_tokens"]) ?? 0
        let cacheCreationInputTokens = integerValue(payload["cache_creation_input_tokens"]) ?? 0
        let cacheReadInputTokens = integerValue(payload["cache_read_input_tokens"]) ?? 0
        let outputTokens = integerValue(payload["output_tokens"]) ?? 0
        let totalInputTokens = inputTokens + cacheCreationInputTokens + cacheReadInputTokens

        guard totalInputTokens > 0 || outputTokens > 0 else { return nil }
        return UsageTotals(
            inputTokens: totalInputTokens,
            cachedInputTokens: cacheReadInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalInputTokens + outputTokens
        )
    }

    private static func preferredUsageTotals(_ lhs: UsageTotals?, _ rhs: UsageTotals) -> UsageTotals {
        guard let lhs else { return rhs }
        return lhs.totalTokens >= rhs.totalTokens ? lhs : rhs
    }

    private static func preferredCursorBubbleMetrics(_ lhs: CursorBubbleMetrics?, _ rhs: CursorBubbleMetrics) -> CursorBubbleMetrics {
        guard let lhs else { return rhs }

        let preferredUsage: UsageTotals? = {
            switch (lhs.usage, rhs.usage) {
            case let (lhsUsage?, rhsUsage?):
                return preferredUsageTotals(lhsUsage, rhsUsage)
            case let (lhsUsage?, nil):
                return lhsUsage
            case let (nil, rhsUsage?):
                return rhsUsage
            default:
                return nil
            }
        }()

        let preferredResponseTimeMs = max(lhs.responseTimeMs ?? 0, rhs.responseTimeMs ?? 0)
        return CursorBubbleMetrics(
            usage: preferredUsage,
            responseTimeMs: preferredResponseTimeMs > 0 ? preferredResponseTimeMs : nil
        )
    }

    private static func applyUsageDelta(from start: UsageTotals?, to end: UsageTotals, on prompt: inout ImportedPrompt) {
        let measured = UsageTotals(
            inputTokens: max(0, end.inputTokens - (start?.inputTokens ?? 0)),
            cachedInputTokens: max(0, end.cachedInputTokens - (start?.cachedInputTokens ?? 0)),
            outputTokens: max(0, end.outputTokens - (start?.outputTokens ?? 0)),
            totalTokens: max(0, end.totalTokens - (start?.totalTokens ?? 0))
        )
        applyMeasuredUsage(measured, on: &prompt)
    }

    private static func applyMeasuredUsage(_ usage: UsageTotals, on prompt: inout ImportedPrompt) {
        guard usage.inputTokens > 0 || usage.outputTokens > 0 || usage.totalTokens > 0 else { return }
        prompt.inputTokens = usage.inputTokens
        prompt.cachedInputTokens = usage.cachedInputTokens
        prompt.outputTokens = usage.outputTokens
        prompt.totalTokens = usage.totalTokens
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String, let parsed = Int(value) {
            return parsed
        }
        return nil
    }

    private static func cursorBubbleResponseTimeMs(from object: [String: Any]) -> Int? {
        guard let timingInfo = object["timingInfo"] as? [String: Any],
              let requestStart = integerValue(timingInfo["clientRpcSendTime"])
        else {
            return nil
        }

        let requestEnd = integerValue(timingInfo["clientSettleTime"])
            ?? integerValue(timingInfo["clientEndTime"])
        guard let requestEnd, requestEnd > requestStart else { return nil }

        let duration = requestEnd - requestStart
        guard duration > 0 else { return nil }
        return duration
    }

    private static func preferredImportedPrompt(_ lhs: ImportedPrompt, _ rhs: ImportedPrompt) -> ImportedPrompt {
        func score(_ prompt: ImportedPrompt) -> Int {
            var total = 0
            if prompt.projectPath != nil { total += 8 }
            if prompt.gitRoot != nil { total += 5 }
            if prompt.sourceContextID != nil { total += 4 }
            if prompt.modelID != nil { total += 2 }
            if prompt.hasMeasuredUsage { total += 2 }
            if prompt.hasMeasuredResponseTime { total += 1 }
            if !prompt.projectName.isEmpty, prompt.projectName != prompt.provider.title { total += 1 }
            if prompt.sourcePath.contains("/workspaceStorage/empty-window/") { total -= 6 }
            return total
        }

        let lhsScore = score(lhs)
        let rhsScore = score(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt ? lhs : rhs
        }
        return lhs
    }

    private static func mergeCodexHistoryPrompts(primary: [ImportedPrompt], history: [ImportedPrompt]) -> [ImportedPrompt] {
        guard !history.isEmpty else { return primary }

        let hintsBySessionID = primary.reduce(into: [String: ImportedPrompt]()) { partialResult, prompt in
            guard let sourceContextID = prompt.sourceContextID else { return }
            if let existing = partialResult[sourceContextID] {
                partialResult[sourceContextID] = preferredImportedPrompt(existing, prompt)
            } else {
                partialResult[sourceContextID] = prompt
            }
        }
        let primaryByBody = Dictionary(grouping: primary, by: \.body)

        var merged = primary
        for prompt in history {
            let enriched: ImportedPrompt = {
                guard let sessionID = prompt.sourceContextID,
                      let hint = hintsBySessionID[sessionID]
                else {
                    return prompt
                }
                return copyingPrompt(
                    prompt,
                    projectPath: hint.projectPath,
                    sourceContextID: sessionID,
                    modelID: hint.modelID
                )
            }()

            let duplicate = (primaryByBody[enriched.body] ?? []).contains { existing in
                codexHistoryPrompt(existing, matches: enriched)
            }
            if !duplicate {
                merged.append(enriched)
            }
        }

        return merged
    }

    private static func codexHistoryPrompt(_ lhs: ImportedPrompt, matches rhs: ImportedPrompt) -> Bool {
        guard lhs.body == rhs.body else { return false }

        if let lhsContextID = lhs.sourceContextID,
           let rhsContextID = rhs.sourceContextID,
           lhsContextID != rhsContextID {
            return false
        }

        return abs(lhs.capturedAt.timeIntervalSince(rhs.capturedAt)) <= 30
    }

    private static func mergeCopilotCommandHistoryPrompts(primary: [ImportedPrompt], history: [ImportedPrompt]) -> [ImportedPrompt] {
        guard !history.isEmpty else { return primary }

        let existingBodies = Set(primary.map(\.body))
        var merged = primary
        for prompt in history {
            if !existingBodies.contains(prompt.body) {
                merged.append(prompt)
            }
        }
        return merged
    }

    private static func forEachJSONObjectLine(in url: URL, body: ([String: Any]) -> Void) {
        enumerateLineData(at: url) { lineData in
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                return
            }
            body(object)
        }
    }

    private static func enumerateLineData(at url: URL, body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        while autoreleasepool(invoking: {
            guard let chunk = try? handle.read(upToCount: streamedReadChunkSize),
                  !chunk.isEmpty
            else {
                return false
            }

            buffer.append(chunk)
            flushCompleteLines(from: &buffer, body: body)
            return true
        }) {}

        if let lineData = normalizedLineData(from: buffer), !lineData.isEmpty {
            body(lineData)
        }
    }

    private static func flushCompleteLines(from buffer: inout Data, body: (Data) -> Void) {
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else { return }

        let completedRange = buffer.startIndex..<lastNewline
        let remainderStart = buffer.index(after: lastNewline)
        let remainder = remainderStart < buffer.endIndex ? Data(buffer[remainderStart...]) : Data()

        for line in buffer[completedRange].split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let lineData = normalizedLineData(from: Data(line)), !lineData.isEmpty {
                body(lineData)
            }
        }

        buffer = remainder
    }

    private static func normalizedLineData(from data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        if data.last == 0x0D {
            return Data(data.dropLast())
        }
        return data
    }

    private static func copyingPrompt(
        _ prompt: ImportedPrompt,
        sourcePath: String? = nil,
        projectPath: String? = nil,
        capturedAt: Date? = nil,
        sourceContextID: String? = nil,
        modelID: String? = nil
    ) -> ImportedPrompt {
        ImportedPrompt(
            id: prompt.id,
            provider: prompt.provider,
            title: prompt.title,
            body: prompt.body,
            sourcePath: sourcePath ?? prompt.sourcePath,
            projectPath: projectPath ?? prompt.projectPath,
            capturedAt: capturedAt ?? prompt.capturedAt,
            metadataOnly: prompt.metadataOnly,
            gitRoot: prompt.gitRoot,
            commitSHA: prompt.commitSHA,
            commitMessage: prompt.commitMessage,
            commitDate: prompt.commitDate,
            commitConfidence: prompt.commitConfidence,
            tags: prompt.tags,
            commitOrphaned: prompt.commitOrphaned,
            sourceContextID: sourceContextID ?? prompt.sourceContextID,
            modelID: modelID ?? prompt.modelID,
            inputTokens: prompt.inputTokens,
            cachedInputTokens: prompt.cachedInputTokens,
            outputTokens: prompt.outputTokens,
            totalTokens: prompt.totalTokens,
            responseTimeMs: prompt.responseTimeMs
        )
    }

    private static func fileFingerprint(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return "\(Int64(modifiedAt.timeIntervalSince1970)):\(size)"
    }

    private static func compositeFingerprint(for urls: [URL]) -> String? {
        let components = urls.compactMap { url -> String? in
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard exists else { return "missing:\(url.lastPathComponent)" }
            return fileFingerprint(for: url)
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "|")
    }

    private static func discoverCodexStateDatabase() -> URL? {
        discoverCodexStateDatabase(homeURL: URL(fileURLWithPath: NSHomeDirectory()))
    }

    private static func discoverCodexStateDatabase(homeURL: URL) -> URL? {
        let fileManager = FileManager.default
        let root = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let searchRoots = [
            root,
            root.appendingPathComponent("sqlite", isDirectory: true)
        ]

        let candidates = searchRoots.flatMap { directory -> [URL] in
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            return files.filter { url in
                url.lastPathComponent == "state.sqlite" || (url.lastPathComponent.hasPrefix("state_") && url.pathExtension == "sqlite")
            }
        }

        return candidates.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private static func loadCodexThreads(from dbURL: URL) -> [CodexThreadRecord]? {
        guard let db = try? openSQLite(dbURL) else {
            Self.runtimeLogger.error("Failed to open Codex state DB", metadata: ["path": dbURL.path])
            return nil
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT id, rollout_path, cwd, updated_at
        FROM threads
        WHERE rollout_path IS NOT NULL AND rollout_path != ''
        ORDER BY updated_at DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var threads: [CodexThreadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let rolloutText = sqlite3_column_text(statement, 1),
                  let cwdText = sqlite3_column_text(statement, 2)
            else {
                continue
            }

            let id = String(cString: idText)
            let rolloutPath = String(cString: rolloutText)
            let cwd = String(cString: cwdText)
            let updatedAt = sqlite3_column_int64(statement, 3)
            let rolloutURL = URL(fileURLWithPath: rolloutPath)
            guard FileManager.default.fileExists(atPath: rolloutURL.path) else { continue }

            threads.append(CodexThreadRecord(
                id: id,
                rolloutURL: rolloutURL,
                cwd: cwd,
                updatedAt: updatedAt
            ))
        }

        return threads
    }

    private static func codexThreadFingerprint(thread: CodexThreadRecord) -> String? {
        // Keep Codex cache invalidation scoped to the individual thread. The state DB
        // file mtime changes whenever any thread is updated, which otherwise forces a
        // full reparse of every rollout transcript on each refresh.
        guard let rolloutFingerprint = fileFingerprint(for: thread.rolloutURL) else {
            return nil
        }
        return "\(thread.id)|\(thread.rolloutURL.path)|\(rolloutFingerprint)|\(thread.updatedAt)|\(thread.cwd)"
    }

    private static func parseWorkspacePath(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folder = object["folder"] as? String
        else {
            return nil
        }
        return normalizedProjectPath(folder)
    }

    private static func copilotUserRoots(homeDirectoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let baseDirectories = [
            homeDirectoryURL.appendingPathComponent("Library/Application Support", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".config", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("AppData/Roaming", isDirectory: true)
        ]

        var discovered: [URL] = []
        var seenPaths = Set<String>()

        func appendIfValid(_ candidate: URL) {
            let standardizedPath = candidate.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else { return }
            guard fileManager.fileExists(atPath: candidate.path) else { return }

            let hasWorkspaceStorage = fileManager.fileExists(
                atPath: candidate.appendingPathComponent("workspaceStorage", isDirectory: true).path
            )
            let hasGlobalSessions = fileManager.fileExists(
                atPath: candidate.appendingPathComponent("globalStorage/emptyWindowChatSessions", isDirectory: true).path
            )
            guard hasWorkspaceStorage || hasGlobalSessions else { return }
            discovered.append(candidate)
        }

        for baseDirectory in baseDirectories where fileManager.fileExists(atPath: baseDirectory.path) {
            appendIfValid(baseDirectory.appendingPathComponent("User", isDirectory: true))

            let children = (try? fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                appendIfValid(child.appendingPathComponent("User", isDirectory: true))
            }
        }

        return discovered
    }

    private static func openSQLite(_ url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CodebookError.sqlite("Failed to open integration store at \(url.path)")
        }
        // Avoid indefinite blocking when another process (e.g. Cursor) holds a write lock.
        sqlite3_busy_timeout(db, 2000)
        return db
    }

    private static func fetchItemValue(db: OpaquePointer?, key: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func cursorGenerationDates(db: OpaquePointer?, key: String) -> [Date] {
        guard let value = fetchItemValue(db: db, key: key),
              let data = value.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return array.compactMap { entry in
            guard let unixMs = entry["unixMs"] as? NSNumber else { return nil }
            return Date(timeIntervalSince1970: unixMs.doubleValue / 1000.0)
        }
    }

    private static func cursorComposerDates(db: OpaquePointer?, key: String) -> [Date] {
        guard let value = fetchItemValue(db: db, key: key),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let composers = object["allComposers"] as? [[String: Any]]
        else {
            return []
        }

        return composers.flatMap { composer in
            [composer["createdAt"], composer["lastUpdatedAt"]].compactMap { raw in
                guard let unixMs = raw as? NSNumber else { return nil }
                return Date(timeIntervalSince1970: unixMs.doubleValue / 1000.0)
            }
        }
    }

    private static func cursorPromptTimestamp(promptIndex: Int, promptCount: Int, generationDates: [Date], fallbackDate: Date) -> Date {
        guard !generationDates.isEmpty else { return fallbackDate }
        if generationDates.count == 1 || promptCount <= 1 {
            return generationDates[min(promptIndex, generationDates.count - 1)]
        }
        let position = Double(promptIndex) / Double(max(promptCount - 1, 1))
        let mappedIndex = Int((position * Double(generationDates.count - 1)).rounded())
        return generationDates[min(max(mappedIndex, 0), generationDates.count - 1)]
    }

    private static func normalizedProjectPath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("file://"), let url = URL(string: raw), url.isFileURL {
            return url.path
        }
        return raw
    }

    private static func isLikelyCodexPrompt(_ text: String) -> Bool {
        isLikelyUserPrompt(text)
    }

    static func isLikelyUserPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowercase = trimmed.lowercased()

        let rejectedPrefixes = [
            "# agents.md instructions",
            "<environment_context>",
            "# context from my ide setup:",
            "## active file:",
            "<instructions>",
            "<skill>",
            "<turn_aborted>",
            "<subagent_notification>",
            "dom path:",
            "position:",
        ]
        if rejectedPrefixes.contains(where: { lowercase.hasPrefix($0) }) {
            return false
        }

        let rejectedSubstrings = [
            "<environment_context>",
            "# context from my ide setup:",
            "<turn_aborted>",
            "<subagent_notification>",
        ]
        if rejectedSubstrings.contains(where: { lowercase.contains($0) }) {
            return false
        }

        if looksLikePastedErrorTrace(lowercase) {
            return false
        }

        return true
    }

    private static func looksLikePastedErrorTrace(_ lowercase: String) -> Bool {
        let firstLine = lowercase.prefix(while: { $0 != "\n" })
        let errorSignatures = [
            "console error",
            "runtime typeerror",
            "runtime error",
            "unhandled runtime error",
        ]
        if errorSignatures.contains(where: { firstLine.hasPrefix($0) }) {
            let lines = lowercase.split(separator: "\n").count
            if lines >= 3 { return true }
        }
        return false
    }

    static func cleanPromptTitle(_ rawTitle: String) -> String {
        let lines = rawTitle.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let skipPrefixes = [
            "# files mentioned by the user:",
            "## screenshot",
            "## my request",
            "<image",
            "dom path:",
        ]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if skipPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
            return trimmed
        }
        return lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTitle
    }

    private static func decodeClaudeProjectPath(from sourceURL: URL) -> String? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
        let relative = sourceURL.path.replacingOccurrences(of: root.path + "/", with: "")
        guard let firstComponent = relative.split(separator: "/").first else { return nil }
        let encoded = String(firstComponent)
        guard encoded.hasPrefix("-Users-") else { return nil }
        let path = encoded.replacingOccurrences(of: "-", with: "/")
        return path.hasPrefix("/Users/") ? path : nil
    }

    private static func claudeSessionID(from sourceURL: URL) -> String? {
        guard sourceURL.pathExtension.lowercased() == "jsonl" else { return nil }
        let identifier = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? nil : identifier
    }

    private static func preferredClaudeProjectPath(cwd: String?, fallback: String?) -> String? {
        let normalized = normalizedProjectPath(cwd)
        guard let normalized else { return fallback }
        let home = NSHomeDirectory()
        if normalized == home || normalized == URL(fileURLWithPath: home).deletingLastPathComponent().path {
            return fallback ?? normalized
        }
        if let fallback, shouldPreferFallbackProjectPath(primary: normalized, fallback: fallback) {
            return fallback
        }
        let depth = normalized.split(separator: "/").count
        if depth <= 2, let fallback {
            return fallback
        }
        return normalized
    }

    private static func shouldPreferFallbackProjectPath(primary: String, fallback: String) -> Bool {
        guard primary != fallback else { return false }
        let primaryDepth = primary.split(separator: "/").count
        let fallbackDepth = fallback.split(separator: "/").count
        if fallbackDepth <= primaryDepth { return false }

        let primaryHasGit = hasGitRoot(primary)
        let fallbackHasGit = hasGitRoot(fallback)
        if fallbackHasGit && !primaryHasGit {
            return true
        }

        if primaryDepth <= 3 && fallbackDepth >= 5 {
            return true
        }
        return false
    }

    private static func hasGitRoot(_ path: String) -> Bool {
        guard let result = try? Shell.run(
            arguments: ["git", "-C", path, "rev-parse", "--show-toplevel"],
            timeout: 2
        ) else {
            return false
        }
        return result.status == 0
    }
}

private struct CursorBubbleMetrics {
    let usage: UsageTotals?
    let responseTimeMs: Int?
}

private struct PromptDedupKey: Hashable {
    let provider: IntegrationProvider
    let title: String
    let body: String
    let sourcePath: String
}

private struct OpenCodeSessionMetadata: Sendable {
    let directory: String?
    let lastActivityAt: Date?
}

private struct OpenCodeCachedPromptKey: Hashable {
    let contextID: String
    let text: String
}

private struct CodexThreadRecord {
    let id: String
    let rolloutURL: URL
    let cwd: String
    let updatedAt: Int64
}

private struct UsageTotals: Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

private struct ProviderScanResult: Sendable {
    let provider: IntegrationProvider
    let prompts: [ImportedPrompt]
    let cacheEntries: [String: IntegrationScanCacheStore.Entry]
    let cacheHits: Int
    let parsedCount: Int
    let scannedSourcePaths: Set<String>

    init(
        provider: IntegrationProvider,
        prompts: [ImportedPrompt] = [],
        cacheEntries: [String: IntegrationScanCacheStore.Entry] = [:],
        cacheHits: Int = 0,
        parsedCount: Int = 0,
        scannedSourcePaths: Set<String> = []
    ) {
        self.provider = provider
        self.prompts = prompts
        self.cacheEntries = cacheEntries
        self.cacheHits = cacheHits
        self.parsedCount = parsedCount
        self.scannedSourcePaths = scannedSourcePaths
    }
}
