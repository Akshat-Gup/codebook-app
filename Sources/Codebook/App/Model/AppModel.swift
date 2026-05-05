import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var pinnedProjectIDs: Set<String>
    @Published var savedPromptIDs: Set<String>
    @Published var savedPromptKeys: Set<String>
    @Published var savedCommitSHAs: Set<String>
    @Published var hiddenProjectIDs: Set<String>
    @Published var hiddenPromptKeys: Set<String>
    @Published var manualFolders: [String]
    @Published var enabledImportedPromptProviders: Set<IntegrationProvider>
    @Published var expandedDayIDs: Set<String> = []
    @Published var expandedGroupIDs: Set<String> = []
    @Published var importedPrompts: [ImportedPrompt] = []
    @Published var importedPromptsRevision: Int = 0
    @Published var selectedProjectID: String?
    @Published var selectedPromptID: String?
    @Published var historyFilterPlatform: IntegrationProvider? = nil
    @Published var historyFilterStartDate: Date? = nil
    @Published var historyFilterEndDate: Date? = nil
    @Published var historyGroupingMode: HistoryGroupingMode
    @Published var searchInputText: String = ""
    @Published var searchText: String = ""
    @Published var searchTab: SearchTab = .all
    @Published var searchMode: SearchMode = .keyword
    @Published var aiSearchResults: [ImportedPrompt] = []
    @Published var aiSearchQuery: String? = nil
    @Published var aiSearchIsRunning = false
    @Published var aiSearchError: String? = nil
    @Published var aiSearchReasoning: String? = nil
    @Published var aiSearchSummary: String? = nil
    @Published var searchFocusRequestID: Int = 0
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var loadingProgress: Double? = nil
    @Published var loadingStatusText: String? = nil
    @Published var settingsPresented = false
    @Published var insightsApiKey: String = ""
    @Published var insightsApiProvider: String = InsightsProvider.openai.rawValue
    @Published var insightsResult: InsightsResult?
    @Published var insightsIsRunning = false
    @Published var insightsError: String?
    @Published var refinedImportedPrompts: [String: String] = [:]
    @Published var refiningImportedPromptID: String? = nil
    @Published var localChangesResult: InsightsResult? = nil
    @Published var localChangesIsRunning = false
    @Published var localChangesError: String? = nil
    @Published var localChangesProjectID: String?
    @Published var selectedRepoAutomationSettings: RepoAutomationSettings?
    @Published var selectedRepoAutomationStatus: RepoAutomationStatus?
    @Published var appVersionDisplay: String
    @Published var appReleaseRepository: String?
    @Published var appReleasePageURL: URL?
    @Published var appcastURL: URL?
    @Published var sparkleConfigured: Bool
    @Published var customProviderProfiles: [CustomProviderProfile]
    @Published var ecosystemSnapshots: [ProviderInstallSnapshot] = []
    @Published var ecosystemDiscoveredInstalledPackages: [EcosystemPackage] = []
    @Published var ecosystemSearchResults: [GitHubPackageSearchResult] = []
    @Published var ecosystemSearchMode: EcosystemSearchMode = .keyword
    @Published var ecosystemSearchIsRunning = false
    @Published var ecosystemSearchSummary: String?
    @Published var agentsSharedBase: String
    @Published var selectedAgentsAdvice: Set<AgentsAdvicePack>
    @Published var agentsProjectAudits: [AgentsProjectAudit] = []
    @Published var harnessSessionStatus: HarnessSessionStatus
    @Published var enabledHarnessProcessNames: Set<String>
    @Published var harnessPollIntervalSeconds: Int
    @Published var harnessMode: HarnessSessionMode
    @Published var harnessCustomDurationSeconds: Int
    @Published var harnessKeepDisplayAwake: Bool
    @Published var harnessPowerAdapterOnly: Bool
    /// Destination tools (Cursor, Codex, …) that receive installs from Ecosystem. Persisted; defaults to all known targets.
    @Published var ecosystemInstallTargetSelection: Set<String> = []

    // MARK: - Architecture Diagram
    @Published var savedDiagrams: [SavedDiagram] = []
    @Published var diagramSVG: String?
    @Published var diagramIsGenerating = false
    @Published var diagramError: String?
    @Published var diagramConversation: [DiagramMessage] = []
    @Published var diagramQuestionIsRunning = false
    @Published var diagramUpdatingID: String? = nil
    /// Kind currently being generated so the matching chip can show progress.
    @Published var diagramGeneratingKind: DiagramKind? = nil
    /// Most recently added diagram so DiagramSheet can auto-select it.
    @Published var diagramLastAddedID: String? = nil
    /// Cached codebase context so follow-up questions don't rescan the filesystem.
    var diagramCodebaseContext: String?

    // MARK: - Cached search results (computed once per search change, reused everywhere)
    @Published var visiblePrompts: [ImportedPrompt] = []
    @Published var dayGroups: [DayPromptGroup] = []
    @Published var searchByCommits: [SearchCommitGroup] = []
    @Published var searchByDates: [SearchDateGroup] = []
    @Published var searchByProjects: [SearchProjectGroup] = []
    @Published var searchByTags: [SearchTagGroup] = []
    @Published var searchByProviders: [SearchProviderGroup] = []
    @Published var searchTabCounts: [SearchTab: Int] = [:]
    @Published var searchTabLoading: SearchTab?
    @Published var projectSummariesCache: [ProjectSummary] = []
    @Published var pinnedProjectSummariesCache: [ProjectSummary] = []
    @Published var otherProjectSummariesCache: [ProjectSummary] = []
    @Published var savedPromptsCache: [ImportedPrompt] = []
    @Published var savedVisiblePromptsCache: [ImportedPrompt] = []
    @Published var savedCommitGroupsCache: [SearchCommitGroup] = []
    @Published var savedDayGroupsCache: [DayPromptGroup] = []
    /// Hidden prompts with the same history filters applied as Saved / library.
    @Published var hiddenVisiblePromptsCache: [ImportedPrompt] = []
    @Published var hiddenPromptGroupsCache: [PromptGroup] = []
    @Published var hiddenProjectsCache: [ProjectSummary] = []
    @Published var hiddenPromptsCache: [ImportedPrompt] = []
    @Published var sessionDayGroupsCache: [SessionDayGroup] = []
    @Published var localChangesProjectOptionsCache: [ProjectSummary] = []
    @Published var automationProjectsCache: [ProjectSummary] = []
    @Published var historyFilterDateBoundsCache: ClosedRange<Date>?

    let cacheStore = ImportedPromptCacheStore()
    let integrationScanCacheStore = IntegrationScanCacheStore()
    let repoAutomationStore: RepoAutomationStore
    let promptAutomationService = PromptAutomationService()
    let promptWorkspaceActionService = PromptWorkspaceActionService()
    let ecosystemWorkspaceService = EcosystemWorkspaceService()
    let gitHubEcosystemSearchService = GitHubEcosystemSearchService()
    let agentsTemplateService = AgentsTemplateService()
    let harnessSessionService = HarnessSessionService()
    let runtimeLogger: RuntimeLogger
    let runtimePolicy: RuntimePolicy
    let defaults: UserDefaults
    let pinnedProjectsKey = "codebook.pinnedProjects"
    let savedPromptIDsKey = "codebook.savedPromptIDs"
    let savedPromptKeysKey = "codebook.savedPromptKeys"
    let savedCommitSHAsKey = "codebook.savedCommitSHAs"
    let hiddenProjectsKey = "codebook.hiddenProjects"
    /// Per-prompt hide list keyed by `ImportedPrompt.stableLibraryKey` (not scan UUID `id` or thread ID).
    let hiddenPromptKeysKey = "codebook.hiddenPromptKeys"
    let legacyHiddenPromptIDsKey = "codebook.hiddenPromptIDs"
    let insightsApiProviderKey = "codebook.insightsApiProvider"
    let manualFoldersKey = "codebook.manualFolders"
    let enabledImportedPromptProvidersKey = "codebook.enabledImportedPromptProviders"
    let historyGroupingModeKey = "codebook.historyGroupingMode"
    let localChangesProjectIDKey = "codebook.localChangesProjectID"
    let customProviderProfilesKey = "codebook.customProviderProfiles"
    let ecosystemInstallTargetIDsKey = "codebook.ecosystemInstallTargetIDs"
    let agentsSharedBaseKey = "codebook.agentsSharedBase"
    let selectedAgentsAdviceKey = "codebook.selectedAgentsAdvice"
    let enabledHarnessProcessNamesKey = "codebook.enabledHarnessProcessNames"
    let harnessPollIntervalSecondsKey = "codebook.harnessPollIntervalSeconds"
    let harnessModeKey = "codebook.harnessMode"
    let harnessCustomDurationSecondsKey = "codebook.harnessCustomDurationSeconds"
    let harnessKeepDisplayAwakeKey = "codebook.harnessKeepDisplayAwake"
    let harnessPowerAdapterOnlyKey = "codebook.harnessPowerAdapterOnly"
    let cliEnabledKey = "codebook.cliEnabled"
    let dataVersionKey = "codebook.integrationDataVersion"
    var currentDataVersion: Int { 15_000 + IntegrationScanner.cacheVersion }
    let searchDebounceDuration: Duration
    let shouldAutoRefresh: Bool
    let liveRefreshPollInterval: Duration
    let liveRefreshFullRescanInterval: Duration
    var searchDebounceTask: Task<Void, Never>?
    var searchTabLoadTask: Task<Void, Never>?
    var aiSearchTask: Task<Void, Never>?
    var liveRefreshPollTask: Task<Void, Never>?
    var liveRefreshFullRescanTask: Task<Void, Never>?
    var harnessStatusRefreshTask: Task<Void, Never>?
    var harnessReinstallDebounceTask: Task<Void, Never>?
    var appDidBecomeActiveObserver: NSObjectProtocol?
    var appDidResignActiveObserver: NSObjectProtocol?
    var lastRefreshCompletedAt: Date?
    var isAppActive = true
    /// Prior snapshot of install destinations; when non-nil, newly discovered target IDs are merged into the selection.
    var lastEcosystemValidInstallTargetIDs: Set<String>?
    let diagramStore = DiagramStore()
    var stagesPartialScanResults = false
    var stagedScanPromptsByProvider: [IntegrationProvider: [ImportedPrompt]] = [:]
    var promptSearchCaches: [String: PromptSearchCache] = [:]
    var promptByID: [String: ImportedPrompt] = [:]
    var loadedSearchTabs: Set<SearchTab> = []
    var searchResultsRevision: Int = 0
    var loadedInsightsAPIKeyProvider: InsightsProvider?

    init(
        importedPrompts initialImportedPrompts: [ImportedPrompt]? = nil,
        searchDebounceDuration: Duration = .milliseconds(120),
        shouldAutoRefresh: Bool = true,
        liveRefreshPollInterval: Duration = .seconds(8),
        liveRefreshFullRescanInterval: Duration = .seconds(180),
        userDefaults: UserDefaults = .standard,
        runtimePolicy: RuntimePolicy = .shared,
        runtimeLogger: RuntimeLogger = .shared,
        releaseMetadata: AppReleaseMetadata = .current
    ) {
        self.searchDebounceDuration = searchDebounceDuration
        self.shouldAutoRefresh = shouldAutoRefresh
        self.liveRefreshPollInterval = liveRefreshPollInterval
        self.liveRefreshFullRescanInterval = liveRefreshFullRescanInterval
        self.defaults = userDefaults
        self.runtimePolicy = runtimePolicy
        self.runtimeLogger = runtimeLogger
        self.repoAutomationStore = RepoAutomationStore(defaults: userDefaults, policy: runtimePolicy)
        self.pinnedProjectIDs = Set(defaults.stringArray(forKey: pinnedProjectsKey) ?? [])
        let legacySavedPromptIDs = Set(defaults.stringArray(forKey: savedPromptIDsKey) ?? [])
        self.savedPromptIDs = legacySavedPromptIDs
        self.savedPromptKeys = Set(defaults.stringArray(forKey: savedPromptKeysKey) ?? [])
        self.savedCommitSHAs = Set(defaults.stringArray(forKey: savedCommitSHAsKey) ?? [])
        self.hiddenProjectIDs = Set(defaults.stringArray(forKey: hiddenProjectsKey) ?? [])
        self.hiddenPromptKeys = Set(defaults.stringArray(forKey: hiddenPromptKeysKey) ?? [])
        if let storedInsightsProvider = defaults.string(forKey: insightsApiProviderKey),
           !storedInsightsProvider.isEmpty {
            self.insightsApiProvider = storedInsightsProvider
        }
        self.manualFolders = (defaults.stringArray(forKey: manualFoldersKey) ?? []).sorted()

        if let storedEnabledProviders = defaults.stringArray(forKey: enabledImportedPromptProvidersKey) {
            let parsedProviders = Set(storedEnabledProviders.compactMap(IntegrationProvider.init(rawValue:)))
            self.enabledImportedPromptProviders = parsedProviders.isEmpty ? Set(IntegrationProvider.allCases) : parsedProviders
        } else {
            self.enabledImportedPromptProviders = Set(IntegrationProvider.allCases)
        }
        if let rawHistoryGroupingMode = defaults.string(forKey: historyGroupingModeKey),
           let parsedHistoryGroupingMode = HistoryGroupingMode(rawValue: rawHistoryGroupingMode) {
            self.historyGroupingMode = parsedHistoryGroupingMode
        } else {
            self.historyGroupingMode = .commit
        }
        self.localChangesProjectID = defaults.string(forKey: localChangesProjectIDKey)
        if let providerData = defaults.data(forKey: customProviderProfilesKey),
           let decoded = try? JSONDecoder().decode([CustomProviderProfile].self, from: providerData) {
            self.customProviderProfiles = decoded
        } else {
            self.customProviderProfiles = []
        }
        self.ecosystemInstallTargetSelection = Set(defaults.stringArray(forKey: ecosystemInstallTargetIDsKey) ?? [])
        self.agentsSharedBase = defaults.string(forKey: agentsSharedBaseKey) ?? AgentsTemplateService().defaultSharedBase()
        if let storedAdvice = defaults.stringArray(forKey: selectedAgentsAdviceKey) {
            self.selectedAgentsAdvice = Set(storedAdvice.compactMap(AgentsAdvicePack.init(rawValue:)))
        } else {
            self.selectedAgentsAdvice = []
        }
        let sessionService = HarnessSessionService()
        let storedHarnessProcesses = Set(defaults.stringArray(forKey: enabledHarnessProcessNamesKey) ?? [])
        let enabledSessionProcesses = storedHarnessProcesses.isEmpty ? Set(sessionService.defaultProcessNames) : storedHarnessProcesses
        self.enabledHarnessProcessNames = enabledSessionProcesses
        let storedPollInterval = defaults.integer(forKey: harnessPollIntervalSecondsKey)
        self.harnessPollIntervalSeconds = storedPollInterval > 0 ? storedPollInterval : 5
        let storedHarnessMode = defaults.string(forKey: harnessModeKey)
            .flatMap(HarnessSessionMode.init(rawValue:)) ?? .agentSessions
        self.harnessMode = storedHarnessMode
        let storedCustomDuration = defaults.integer(forKey: harnessCustomDurationSecondsKey)
        self.harnessCustomDurationSeconds = storedCustomDuration > 0 ? storedCustomDuration : 3 * 60 * 60
        self.harnessKeepDisplayAwake = defaults.bool(forKey: harnessKeepDisplayAwakeKey)
        self.harnessPowerAdapterOnly = defaults.bool(forKey: harnessPowerAdapterOnlyKey)
        self.harnessSessionStatus = HarnessSessionStatus(
            isInstalled: false,
            isRunning: false,
            isKeepingAwake: false,
            activeProcessName: nil,
            watchedProcessNames: Array(enabledSessionProcesses).sorted(),
            logPath: sessionService.logURL.path
        )
        self.appVersionDisplay = releaseMetadata.versionDisplay
        self.appReleaseRepository = releaseMetadata.githubRepository
        self.appReleasePageURL = releaseMetadata.releasesURL
        self.appcastURL = releaseMetadata.appcastURL
        self.sparkleConfigured = releaseMetadata.sparkleConfigured
        let loadedPrompts = initialImportedPrompts ?? cacheStore.load(allowedProviders: enabledImportedPromptProviders)
        importedPrompts = loadedPrompts.filter { enabledImportedPromptProviders.contains($0.provider) }
        importedPromptsRevision = 1
        if importedPrompts.isEmpty {
            runtimeLogger.info("AppModel init", metadata: ["mode": "integrations", "cache": "miss"])
        } else {
            runtimeLogger.info("AppModel init", metadata: ["mode": "integrations", "cache": "hit", "count": "\(importedPrompts.count)"])
            let prompts = importedPrompts
            let store = integrationScanCacheStore
            Task.detached(priority: .utility) { store.seedIfNeeded(from: prompts) }
        }
        self.savedDiagrams = diagramStore.load()
        migrateLegacyPromptStateIfNeeded()
        normalizeSavedState()
        rebuildPromptSearchCaches()
        rebuildDerivedPromptCaches()
        selectedProjectID = projectSummaries.first?.id
        recomputeSearchResults()
        normalizeLocalChangesProjectSelection()
        selectedPromptID = visiblePrompts.first?.id
        refreshSelectedRepoAutomationState()
        refreshEcosystemSnapshots()
        refreshAgentsProjectAudits()
        let cacheFresh = cacheStore.isFresh(maxAge: 15 * 60)
        let needsDataUpgrade = runtimePolicy.persistentStorageEnabled && defaults.integer(forKey: dataVersionKey) < currentDataVersion
        if runtimePolicy.persistentStorageEnabled,
           defaults.object(forKey: enabledImportedPromptProvidersKey) == nil {
            persist(IntegrationProvider.allCases.map(\.rawValue).sorted(), forKey: enabledImportedPromptProvidersKey)
        }
        if shouldAutoRefresh && hasEnabledImportedPromptProviders && (importedPrompts.isEmpty || !cacheFresh || needsDataUpgrade) {
            if needsDataUpgrade {
                runtimeLogger.info("Forcing refresh", metadata: ["reason": "data-upgrade", "version": "\(currentDataVersion)"])
            }
            Task { await refresh(forceScan: needsDataUpgrade) }
        } else {
            runtimeLogger.info("Skipped auto refresh", metadata: ["reason": hasEnabledImportedPromptProviders ? "fresh-cache" : "no-enabled-providers"])
        }

        if shouldAutoRefresh {
            isAppActive = NSApplication.shared.isActive
            appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.isAppActive = true
                    guard self.hasEnabledImportedPromptProviders, !self.isRefreshing else { return }
                    await self.refresh()
                }
            }
            appDidResignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.isAppActive = false
                }
            }
            startLiveRefreshLoops()
        }
        refreshHarnessSessionStatus()
    }

    var projectSummaries: [ProjectSummary] {
        projectSummariesCache
    }

    var pinnedProjectSummaries: [ProjectSummary] {
        pinnedProjectSummariesCache
    }

    var otherProjectSummaries: [ProjectSummary] {
        otherProjectSummariesCache
    }

    var selectedProjectSummary: ProjectSummary? {
        projectSummaries.first(where: { $0.id == selectedProjectID })
    }

    var isDashboardSelected: Bool {
        selectedProjectID == "dashboard"
    }

    var isInsightsSelected: Bool {
        selectedProjectID == "insights"
    }

    var isSavedSelected: Bool {
        selectedProjectID == "saved"
    }

    var isHiddenProjectsSelected: Bool {
        selectedProjectID == "hidden-projects"
    }

    var isAutomationsSelected: Bool {
        selectedProjectID == "automations"
    }

    var isEcosystemSelected: Bool {
        selectedProjectID == "ecosystem"
    }

    var selectedInsightsProvider: InsightsProvider {
        InsightsProvider(rawValue: insightsApiProvider) ?? .openai
    }

    var insightsAIAvailable: Bool {
        !insightsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var insightsAvailabilityHelpText: String {
        insightsAIAvailable
            ? "Use the saved \(selectedInsightsProvider.title) API key."
            : "Add a \(selectedInsightsProvider.title) API key in Settings."
    }

    var insightsEmptyStateMessage: String {
        "Add a \(selectedInsightsProvider.title) API key in Settings to use AI features."
    }

    var ecosystemCatalog: [EcosystemPackage] {
        ecosystemWorkspaceService.bundledCatalog()
    }

    var ecosystemInstallTargets: [ProviderInstallDestination] {
        ecosystemWorkspaceService.installTargets(customProviders: customProviderProfiles)
    }

    /// Global provider roots (for example `~/.cursor/skills`), excluding custom profiles tied to a project workspace.
    var ecosystemGlobalInstallTargets: [ProviderInstallDestination] {
        ecosystemInstallTargets.filter(\.isBuiltIn)
    }

    var ecosystemAttentionCount: Int {
        ecosystemSnapshots.filter { $0.existingKinds.isEmpty }.count
    }

    var agentsProjects: [ProjectSummary] {
        localChangesProjectOptions
    }

    var agentsAttentionCount: Int {
        agentsProjectAudits.filter { $0.statusText != "Aligned" }.count
    }

    var savedPrompts: [ImportedPrompt] {
        savedPromptsCache
    }

    var savedVisiblePrompts: [ImportedPrompt] {
        savedVisiblePromptsCache
    }

    var savedCommitGroups: [SearchCommitGroup] {
        savedCommitGroupsCache
    }

    var savedItemCount: Int {
        savedPromptsCache.count + savedCommitGroupsCache.count
    }

    var savedDayGroups: [DayPromptGroup] {
        savedDayGroupsCache
    }

    var hiddenVisiblePrompts: [ImportedPrompt] {
        hiddenVisiblePromptsCache
    }

    var hiddenPromptGroups: [PromptGroup] {
        hiddenPromptGroupsCache
    }

    var hasVisibleHiddenLibraryItems: Bool {
        !hiddenProjects.isEmpty || !hiddenVisiblePrompts.isEmpty
    }

    var hasActiveHistoryFilters: Bool {
        historyFilterPlatform != nil || historyFilterStartDate != nil || historyFilterEndDate != nil
    }

    var historyFilterDateBounds: ClosedRange<Date>? {
        historyFilterDateBoundsCache
    }

    var selectedPrompt: ImportedPrompt? {
        guard let selectedPromptID else { return nil }
        return promptByID[selectedPromptID]
    }

    var hasEnabledImportedPromptProviders: Bool {
        !enabledImportedPromptProviders.isEmpty
    }

    var hiddenProjects: [ProjectSummary] {
        hiddenProjectsCache
    }

    /// Individual prompts hidden from history (listed under **Hidden** alongside hidden projects).
    var hiddenPrompts: [ImportedPrompt] {
        hiddenPromptsCache
    }

    var isReadOnlyMode: Bool {
        runtimePolicy.readOnly
    }

    var isDiagnosticsEnabled: Bool {
        runtimeLogger.isEnabled
    }

    /// CLI ships with the app by default. Keep the user-default override as an emergency opt-out.
    var isCLIEnabled: Bool {
        guard defaults.object(forKey: cliEnabledKey) != nil else { return true }
        return defaults.bool(forKey: cliEnabledKey)
    }

    var localChangesProjectOptions: [ProjectSummary] {
        localChangesProjectOptionsCache
    }

    var automationProjects: [ProjectSummary] {
        automationProjectsCache
    }

    func refresh(forceScan: Bool = false) async {
        isRefreshing = true
        loadingProgress = 0.03
        loadingStatusText = "Scanning prompt history…"
        stagesPartialScanResults = importedPrompts.isEmpty
        stagedScanPromptsByProvider = [:]
        runtimeLogger.info("History scan started", metadata: ["force": forceScan ? "true" : "false"])
        defer {
            isRefreshing = false
            loadingProgress = nil
            loadingStatusText = nil
            stagesPartialScanResults = false
            stagedScanPromptsByProvider = [:]
        }

        let enabledProviders = enabledImportedPromptProviders
        guard !enabledProviders.isEmpty else {
            importedPrompts = []
            importedPromptsRevision &+= 1
            rebuildPromptSearchCaches()
            rebuildDerivedPromptCaches()
            let cs = cacheStore
            let iscs = integrationScanCacheStore
            Task.detached(priority: .utility) {
                cs.save([])
                iscs.save([:])
            }
            recomputeSearchResults()
            normalizeLocalChangesProjectSelection()
            preserveSelection()
            runtimeLogger.info("History scan skipped", metadata: ["reason": "no-enabled-providers"])
            return
        }

        let progressRelay = ScanProgressRelay { [weak self] progress in
            self?.applyScanProgress(progress)
        }
        let refreshOutcome = await Task.detached(priority: .userInitiated) {
            let scanStartedAt = Date()
            let scanned = await IntegrationScanner().scanAll(
                enabledProviders: enabledProviders,
                forceRescan: forceScan,
                progress: { progress in
                    await progressRelay.report(progress)
                }
            )
            let scanDurationMs = Int(Date().timeIntervalSince(scanStartedAt) * 1000)

            let enrichStartedAt = Date()
            let enriched = ImportedPromptEnricher().enrich(scanned)
            let enrichDurationMs = Int(Date().timeIntervalSince(enrichStartedAt) * 1000)

            return (enriched, scanDurationMs, enrichDurationMs)
        }.value
        let enriched = refreshOutcome.0
        let scanDurationMs = refreshOutcome.1
        let enrichDurationMs = refreshOutcome.2

        loadingProgress = 0.94
        loadingStatusText = "Finalizing library…"
        let cs = cacheStore
        Task.detached(priority: .utility) { cs.save(enriched) }
        persist(currentDataVersion, forKey: dataVersionKey)
        lastRefreshCompletedAt = Date()

        guard enriched != importedPrompts else {
            runtimeLogger.info("History scan completed", metadata: [
                "count": "\(enriched.count)",
                "changed": "false",
                "force": forceScan ? "true" : "false",
                "scanMs": "\(scanDurationMs)",
                "enrichMs": "\(enrichDurationMs)"
            ])
            return
        }

        importedPrompts = enriched
        importedPromptsRevision &+= 1
        migrateLegacyPromptStateIfNeeded()
        normalizeSavedState()
        rebuildPromptSearchCaches()
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        normalizeLocalChangesProjectSelection()
        refreshSelectedRepoAutomationState()
        syncConfiguredRepoAutomationsIfNeeded(prompts: enriched)
        refreshAgentsProjectAudits()
        preserveSelection()
        runtimeLogger.info("History scan completed", metadata: [
            "count": "\(enriched.count)",
            "changed": "true",
            "force": forceScan ? "true" : "false",
            "scanMs": "\(scanDurationMs)",
            "enrichMs": "\(enrichDurationMs)"
        ])
    }

    func startLiveRefreshLoops() {
        liveRefreshPollTask?.cancel()
        liveRefreshPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: liveRefreshPollInterval)
                guard !Task.isCancelled else { break }
                await self.performScheduledRefreshIfNeeded(forceScan: false)
            }
        }

        liveRefreshFullRescanTask?.cancel()
        liveRefreshFullRescanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: liveRefreshFullRescanInterval)
                guard !Task.isCancelled else { break }
                await self.performScheduledRefreshIfNeeded(forceScan: true)
            }
        }
    }

    func performScheduledRefreshIfNeeded(forceScan: Bool) async {
        guard shouldAutoRefresh, isAppActive, hasEnabledImportedPromptProviders, !isRefreshing else {
            return
        }

        if !forceScan,
           let lastRefreshCompletedAt,
           Date().timeIntervalSince(lastRefreshCompletedAt) < 4 {
            return
        }

        await refresh(forceScan: forceScan)
    }

    func selectProject(_ project: ProjectSummary) {
        selectedProjectID = project.id
        recomputeSearchResults()
        preserveSelection()
        refreshSelectedRepoAutomationState()
    }

    func setHistoryFilterPlatform(_ platform: IntegrationProvider?) {
        historyFilterPlatform = platform
        historyFiltersDidChange()
    }

    func setHistoryFilterStartDate(_ date: Date?) {
        historyFilterStartDate = date.map(Self.startOfDay(for:))
        if let start = historyFilterStartDate,
           let end = historyFilterEndDate,
           start > end {
            historyFilterEndDate = start
        }
        historyFiltersDidChange()
    }

    func setHistoryFilterEndDate(_ date: Date?) {
        historyFilterEndDate = date.map(Self.endOfDay(for:))
        if let start = historyFilterStartDate,
           let end = historyFilterEndDate,
           end < start {
            historyFilterStartDate = Self.startOfDay(for: end)
        }
        historyFiltersDidChange()
    }

    func setHistoryGroupingMode(_ mode: HistoryGroupingMode) {
        guard historyGroupingMode != mode else { return }
        historyGroupingMode = mode
        defaults.set(mode.rawValue, forKey: historyGroupingModeKey)
        dayGroups = Self.buildDayGroups(from: visiblePrompts, groupingMode: mode)
        savedDayGroupsCache = Self.buildDayGroups(from: savedVisiblePromptsCache, groupingMode: mode)
        hiddenPromptGroupsCache = Self.buildPromptGroups(from: hiddenVisiblePromptsCache, groupingMode: mode)
        preserveSelection()
    }

    func clearHistoryFilters() {
        historyFilterPlatform = nil
        historyFilterStartDate = nil
        historyFilterEndDate = nil
        historyFiltersDidChange()
    }

    func selectDashboard() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "dashboard"
        selectedPromptID = nil
        refreshSelectedRepoAutomationState()
    }

    func selectInsights() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "insights"
        selectedPromptID = nil
        refreshSelectedRepoAutomationState()
    }

    func selectSaved() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "saved"
        selectedPromptID = preferredSavedPromptID
        refreshSelectedRepoAutomationState()
    }

    func selectHiddenProjects() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "hidden-projects"
        selectedPromptID = preferredHiddenPromptID
        refreshSelectedRepoAutomationState()
    }

    func selectAutomations() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "automations"
        selectedPromptID = nil
        refreshSelectedRepoAutomationState()
    }

    func selectEcosystem() {
        applySearchText("")
        searchInputText = ""
        selectedProjectID = "ecosystem"
        selectedPromptID = nil
        refreshSelectedRepoAutomationState()
        refreshEcosystemSnapshots()
        refreshAgentsProjectAudits()
    }

    func selectAllEcosystemInstallTargets() {
        updateEcosystemInstallTargetSelection(Set(ecosystemInstallTargets.map(\.id)))
    }

    func toggleEcosystemInstallTarget(id: String, enabled: Bool) {
        var next = ecosystemInstallTargetSelection
        if enabled {
            next.insert(id)
        } else {
            next.remove(id)
        }
        updateEcosystemInstallTargetSelection(next)
    }

    func updateEcosystemInstallTargetSelection(_ ids: Set<String>) {
        let valid = Set(ecosystemInstallTargets.map(\.id))
        var next = ids.intersection(valid)
        if next.isEmpty, let sole = valid.first {
            next = [sole]
        }
        if next == ecosystemInstallTargetSelection { return }
        ecosystemInstallTargetSelection = next
        persist(Array(next).sorted(), forKey: ecosystemInstallTargetIDsKey)
    }

    func saveInsightsApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = selectedInsightsProvider
        insightsApiKey = trimmed
        loadedInsightsAPIKeyProvider = provider
        KeychainStore.saveAPIKey(trimmed, for: provider)
    }

    func persistInsightsApiProvider(_ raw: String) {
        insightsApiProvider = raw
        defaults.set(raw, forKey: insightsApiProviderKey)
        loadInsightsApiKeyIfNeeded(force: true)
    }

    func loadInsightsApiKeyIfNeeded(force: Bool = false) {
        let provider = selectedInsightsProvider
        guard force || loadedInsightsAPIKeyProvider != provider else { return }
        insightsApiKey = KeychainStore.loadAPIKey(for: provider)
        loadedInsightsAPIKeyProvider = provider
    }

    func resolveInsightsCredentials(for provider: InsightsProvider? = nil) throws -> ResolvedInsightsCredentials {
        let selectedProvider = provider ?? selectedInsightsProvider
        let rawKey: String
        if loadedInsightsAPIKeyProvider == selectedProvider {
            rawKey = insightsApiKey
        } else {
            rawKey = KeychainStore.loadAPIKey(for: selectedProvider)
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CodebookError.network("Add a \(selectedProvider.title) API key in Settings to continue.")
        }
        return ResolvedInsightsCredentials(provider: selectedProvider, apiKey: trimmedKey)
    }

    func runInsightsAnalysis() {
        loadInsightsApiKeyIfNeeded()
        let credentials: ResolvedInsightsCredentials
        do {
            credentials = try resolveInsightsCredentials()
        } catch {
            insightsError = error.localizedDescription
            return
        }
        let prompts = importedPrompts.filter(isPromptVisibleInLibrary)
        guard !prompts.isEmpty else {
            insightsResult = nil
            insightsError = "Import prompt history to analyze prompting patterns."
            return
        }
        insightsIsRunning = true
        insightsError = nil
        insightsResult = nil
        Task {
            do {
                let result = try await InsightsAnalyzer().analyze(
                    prompts: prompts,
                    credentials: credentials
                )
                await MainActor.run {
                    self.insightsResult = result
                    self.insightsIsRunning = false
                }
            } catch {
                await MainActor.run {
                    self.insightsError = error.localizedDescription
                    self.insightsIsRunning = false
                }
            }
        }
    }

    func analyzeLocalChanges() {
        loadInsightsApiKeyIfNeeded()
        let credentials: ResolvedInsightsCredentials
        do {
            credentials = try resolveInsightsCredentials()
        } catch {
            localChangesError = error.localizedDescription
            settingsPresented = true
            return
        }
        let selectedProjectPath = localChangesProjectID.flatMap { selectedID in
            localChangesProjectOptions.first(where: { $0.id == selectedID })?.path
        }
        let workspacePath = selectedProjectPath
            ?? currentWorkspacePath
            ?? localChangesProjectOptions.first?.path
        guard let workspacePath else {
            localChangesError = "Add a project folder to analyze local changes."
            return
        }
        if selectedProjectPath == nil,
           let fallbackID = localChangesProjectOptions.first(where: { $0.path == workspacePath })?.id {
            selectLocalChangesProject(fallbackID)
        }
        localChangesIsRunning = true
        localChangesError = nil
        localChangesResult = nil
        Task {
            do {
                let result = try await InsightsAnalyzer().analyzeLocalChanges(
                    workspacePath: workspacePath,
                    credentials: credentials
                )
                await MainActor.run {
                    self.localChangesResult = result
                    self.localChangesIsRunning = false
                }
            } catch {
                await MainActor.run {
                    self.localChangesError = error.localizedDescription
                    self.localChangesIsRunning = false
                }
            }
        }
    }

    func selectLocalChangesProject(_ projectID: String?) {
        localChangesProjectID = projectID
        persist(projectID, forKey: localChangesProjectIDKey)
    }

    func refineImportedPrompt(_ prompt: ImportedPrompt) {
        loadInsightsApiKeyIfNeeded()
        guard insightsAIAvailable else {
            settingsPresented = true
            return
        }
        refiningImportedPromptID = prompt.id
        Task {
            do {
                let refined = try await refinePromptText(prompt.body, provider: selectedInsightsProvider)
                await MainActor.run {
                    self.refinedImportedPrompts[prompt.id] = refined
                    self.refiningImportedPromptID = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Refinement failed: \(error.localizedDescription)"
                    self.refiningImportedPromptID = nil
                }
            }
        }
    }

    func dismissRefinedPrompt(_ id: String) {
        refinedImportedPrompts.removeValue(forKey: id)
    }

    func requestSearchFocus() {
        searchFocusRequestID &+= 1
    }

    func selectSearchTab(_ tab: SearchTab) {
        guard searchTab != tab else {
            loadSearchTabIfNeeded(tab)
            return
        }
        searchTab = tab
        loadSearchTabIfNeeded(tab)
    }

    func isProjectPinned(_ projectID: String) -> Bool {
        pinnedProjectIDs.contains(projectID)
    }

    func togglePinnedProject(_ projectID: String) {
        if projectID == "all-projects" { return }
        var updatedPinnedProjectIDs = pinnedProjectIDs
        if updatedPinnedProjectIDs.contains(projectID) {
            updatedPinnedProjectIDs.remove(projectID)
        } else {
            updatedPinnedProjectIDs.insert(projectID)
        }
        pinnedProjectIDs = updatedPinnedProjectIDs
        persist(Array(pinnedProjectIDs).sorted(), forKey: pinnedProjectsKey)
        rebuildDerivedPromptCaches()
    }

    func isPromptSaved(_ promptID: String) -> Bool {
        if let prompt = promptByID[promptID] {
            return savedPromptKeys.contains(prompt.stableLibraryKey)
        }
        return savedPromptIDs.contains(promptID)
    }

    func isPromptHidden(_ prompt: ImportedPrompt) -> Bool {
        hiddenPromptKeys.contains(prompt.stableLibraryKey)
    }

    func toggleSavedPrompt(_ prompt: ImportedPrompt) {
        let key = prompt.stableLibraryKey
        if savedPromptKeys.contains(key) {
            savedPromptKeys.remove(key)
        } else {
            savedPromptKeys.insert(key)
        }
        syncSavedPromptIDs()
        persist(Array(savedPromptKeys).sorted(), forKey: savedPromptKeysKey)
        rebuildDerivedPromptCaches()
        preserveSelection()
    }

    func hidePrompt(_ prompt: ImportedPrompt) {
        hidePrompts([prompt], preservingSelectionFor: prompt.id)
    }

    func hidePrompts(_ prompts: [ImportedPrompt]) {
        hidePrompts(prompts, preservingSelectionFor: nil)
    }

    func hidePrompts(_ prompts: [ImportedPrompt], preservingSelectionFor promptID: String?) {
        let keys = Set(prompts.map(\.stableLibraryKey))
        guard !keys.isEmpty else { return }
        let next = hiddenPromptKeys.union(keys)
        guard next != hiddenPromptKeys else { return }
        hiddenPromptKeys = next
        persist(Array(hiddenPromptKeys).sorted(), forKey: hiddenPromptKeysKey)
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        if let promptID, selectedPromptID == promptID {
            return
        }
        preserveSelection()
    }

    func showPrompts(_ prompts: [ImportedPrompt]) {
        let keys = Set(prompts.map(\.stableLibraryKey))
        guard !keys.isEmpty else { return }
        let next = hiddenPromptKeys.subtracting(keys)
        guard next != hiddenPromptKeys else { return }
        hiddenPromptKeys = next
        persist(Array(hiddenPromptKeys).sorted(), forKey: hiddenPromptKeysKey)
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        preserveSelection()
        leaveHiddenPaneIfNowEmpty()
    }

    func areAllPromptsHidden(_ prompts: [ImportedPrompt]) -> Bool {
        let keys = Set(prompts.map(\.stableLibraryKey))
        guard !keys.isEmpty else { return false }
        return keys.isSubset(of: hiddenPromptKeys)
    }

    func areAnyPromptsHidden(_ prompts: [ImportedPrompt]) -> Bool {
        prompts.contains { hiddenPromptKeys.contains($0.stableLibraryKey) }
    }

    func showPrompt(_ prompt: ImportedPrompt) {
        showPrompts([prompt])
    }

    func togglePromptVisibility(_ prompts: [ImportedPrompt]) {
        if areAllPromptsHidden(prompts) {
            showPrompts(prompts)
        } else {
            hidePrompts(prompts)
        }
    }

    func hideCommit(_ sha: String) {
        hidePrompts(importedPrompts.filter { $0.commitSHA == sha })
    }

    func showCommit(_ sha: String) {
        showPrompts(importedPrompts.filter { $0.commitSHA == sha })
    }

    /// After unhiding the last item, leave **Hidden** so the sidebar row can disappear without a stranded pane.
    func leaveHiddenPaneIfNowEmpty() {
        guard isHiddenProjectsSelected, hiddenProjects.isEmpty, hiddenPrompts.isEmpty else { return }
        selectedProjectID = "all-projects"
        recomputeSearchResults()
        preserveSelection()
        refreshSelectedRepoAutomationState()
    }

    func isDaySaved(_ prompts: [ImportedPrompt]) -> Bool {
        let promptKeys = Set(prompts.map(\.stableLibraryKey))
        guard !promptKeys.isEmpty else { return false }
        return promptKeys.isSubset(of: savedPromptKeys)
    }

    func toggleSavedDay(_ prompts: [ImportedPrompt]) {
        let promptKeys = Set(prompts.map(\.stableLibraryKey))
        guard !promptKeys.isEmpty else { return }

        if promptKeys.isSubset(of: savedPromptKeys) {
            savedPromptKeys.subtract(promptKeys)
        } else {
            savedPromptKeys.formUnion(promptKeys)
        }

        syncSavedPromptIDs()
        persist(Array(savedPromptKeys).sorted(), forKey: savedPromptKeysKey)
        rebuildDerivedPromptCaches()
        preserveSelection()
    }

    func isCommitSaved(_ sha: String) -> Bool {
        savedCommitSHAs.contains(sha)
    }

    func toggleSavedCommit(_ sha: String) {
        if savedCommitSHAs.contains(sha) {
            savedCommitSHAs.remove(sha)
        } else {
            savedCommitSHAs.insert(sha)
        }
        persist(Array(savedCommitSHAs).sorted(), forKey: savedCommitSHAsKey)
        rebuildDerivedPromptCaches()
        preserveSelection()
    }

    func isImportedPromptProviderEnabled(_ provider: IntegrationProvider) -> Bool {
        enabledImportedPromptProviders.contains(provider)
    }

    func setImportedPromptProvider(_ provider: IntegrationProvider, enabled: Bool) {
        if enabled {
            enabledImportedPromptProviders.insert(provider)
        } else {
            enabledImportedPromptProviders.remove(provider)
        }

        persist(Array(enabledImportedPromptProviders).map(\.rawValue).sorted(), forKey: enabledImportedPromptProvidersKey)
        importedPrompts = importedPrompts.filter { enabledImportedPromptProviders.contains($0.provider) }
        importedPromptsRevision &+= 1
        migrateLegacyPromptStateIfNeeded()
        normalizeSavedState()
        rebuildPromptSearchCaches()
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        normalizeLocalChangesProjectSelection()
        preserveSelection()
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !manualFolders.contains(path) else { return }
        manualFolders.append(path)
        manualFolders.sort()
        persist(manualFolders, forKey: manualFoldersKey)
        hiddenProjectIDs.remove(path)
        persist(Array(hiddenProjectIDs).sorted(), forKey: hiddenProjectsKey)
        rebuildDerivedPromptCaches()
        refreshAgentsProjectAudits()
        Task { await refresh() }
    }

    func hideProject(_ projectID: String) {
        guard projectID != "all-projects" else { return }
        hiddenProjectIDs.insert(projectID)
        persist(Array(hiddenProjectIDs).sorted(), forKey: hiddenProjectsKey)
        rebuildDerivedPromptCaches()
        if selectedProjectID == projectID {
            selectedProjectID = "all-projects"
            recomputeSearchResults()
            preserveSelection()
            refreshSelectedRepoAutomationState()
        }
        refreshAgentsProjectAudits()
    }

    func showProject(_ projectID: String) {
        hiddenProjectIDs.remove(projectID)
        persist(Array(hiddenProjectIDs).sorted(), forKey: hiddenProjectsKey)
        rebuildDerivedPromptCaches()
        refreshAgentsProjectAudits()
        leaveHiddenPaneIfNowEmpty()
    }

    func removeManualFolder(_ path: String) {
        manualFolders.removeAll { $0 == path }
        persist(manualFolders, forKey: manualFoldersKey)
        hiddenProjectIDs.remove(path)
        var updatedPinnedProjectIDs = pinnedProjectIDs
        updatedPinnedProjectIDs.remove(path)
        pinnedProjectIDs = updatedPinnedProjectIDs
        persist(Array(hiddenProjectIDs).sorted(), forKey: hiddenProjectsKey)
        persist(Array(pinnedProjectIDs).sorted(), forKey: pinnedProjectsKey)
        rebuildDerivedPromptCaches()
        if selectedProjectID == path {
            selectedProjectID = "all-projects"
            recomputeSearchResults()
            preserveSelection()
        }
        refreshSelectedRepoAutomationState()
        refreshAgentsProjectAudits()
    }

    func setAgentsSharedBase(_ value: String) {
        agentsSharedBase = value
        persist(value, forKey: agentsSharedBaseKey)
        refreshAgentsProjectAudits()
    }

    func setAgentsAdvicePack(_ pack: AgentsAdvicePack, enabled: Bool) {
        if enabled {
            selectedAgentsAdvice.insert(pack)
        } else {
            selectedAgentsAdvice.remove(pack)
        }
        persist(Array(selectedAgentsAdvice).map(\.rawValue).sorted(), forKey: selectedAgentsAdviceKey)
        refreshAgentsProjectAudits()
    }

    func addCustomProviderProfile(name: String, rootPath: String) {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPath.isEmpty else {
            errorMessage = "Enter both a provider name and a root path."
            return
        }
        customProviderProfiles.append(CustomProviderProfile(name: trimmedName, rootPath: trimmedPath))
        persistCustomProviderProfiles()
        refreshEcosystemSnapshots()
    }

    func removeCustomProviderProfile(id: String) {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        customProviderProfiles.removeAll { $0.id == id }
        persistCustomProviderProfiles()
        refreshEcosystemSnapshots()
    }

    func installEcosystemPackage(_ package: EcosystemPackage, targetIDs: Set<String>) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        let targets = ecosystemInstallTargets.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = "Select at least one provider destination."
            return
        }

        do {
            let urls = try ecosystemWorkspaceService.installBundledPackage(package, on: targets)
            refreshEcosystemSnapshots()
            if let first = urls.first {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCustomSkill(name: String, summary: String, targetIDs: Set<String>) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        let targets = ecosystemInstallTargets.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = "Select at least one provider destination."
            return
        }

        do {
            _ = try ecosystemWorkspaceService.createCustomSkill(named: name, summary: summary, on: targets)
            refreshEcosystemSnapshots()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installGitHubPackage(urlString: String, kind: EcosystemPackageKind, targetIDs: Set<String>) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        let targets = ecosystemInstallTargets.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = "Select at least one provider destination."
            return
        }

        do {
            let urls = try ecosystemWorkspaceService.installGitHubRepository(urlString: urlString, kind: kind, on: targets)
            refreshEcosystemSnapshots()
            if let first = urls.first {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstallEcosystemPackage(_ package: EcosystemPackage, targetIDs: Set<String>) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        let targets = ecosystemInstallTargets.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = "Select at least one destination to remove from."
            return
        }

        do {
            try ecosystemWorkspaceService.uninstallPackage(package, on: targets)
            refreshEcosystemSnapshots()
            // Reveal the parent folder of the first target so the user can confirm removal.
            if let firstTarget = targets.first {
                let parentURL = URL(fileURLWithPath: firstTarget.path(for: package.kind), isDirectory: true)
                NSWorkspace.shared.activateFileViewerSelecting([parentURL])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reveal an installed package's folder in Finder.
    func revealInstalledPackageInFinder(_ package: EcosystemPackage) {
        guard let target = ecosystemInstallTargets.first(where: { isEcosystemPackageInstalled(package, targetID: $0.id) }) else { return }
        let parentURL = URL(fileURLWithPath: target.path(for: package.kind), isDirectory: true)
        let packageDir = parentURL.appendingPathComponent(Slug.make(from: package.name), isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([packageDir])
    }

    func searchEcosystemGitHub(query: String, kind: EcosystemPackageKind?) async {
        ecosystemSearchIsRunning = true
        ecosystemSearchSummary = nil
        defer { ecosystemSearchIsRunning = false }

        do {
            loadInsightsApiKeyIfNeeded()
            let credentials: ResolvedInsightsCredentials?
            if ecosystemSearchMode == .ai {
                credentials = try? resolveInsightsCredentials()
            } else {
                credentials = nil
            }
            let response = try await gitHubEcosystemSearchService.search(
                query: query,
                kind: kind,
                mode: ecosystemSearchMode,
                provider: selectedInsightsProvider,
                credentials: credentials
            )
            if response.usedAIReranking, credentials != nil {
            }
            ecosystemSearchResults = response.results
            ecosystemSearchSummary = response.summary
        } catch {
            ecosystemSearchResults = []
            ecosystemSearchSummary = nil
            errorMessage = error.localizedDescription
        }
    }

    func clearEcosystemSearch() {
        ecosystemSearchResults = []
        ecosystemSearchSummary = nil
    }

    func openInstallTarget(_ target: ProviderInstallDestination, kind: EcosystemPackageKind? = nil) {
        let path = kind.map { target.path(for: $0) } ?? target.rootPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func isEcosystemPackageInstalled(_ package: EcosystemPackage, targetID: String) -> Bool {
        guard let target = ecosystemInstallTargets.first(where: { $0.id == targetID }) else { return false }
        return ecosystemWorkspaceService.isInstalled(package, on: target)
    }

    func isEcosystemPackageInstalledGlobally(_ package: EcosystemPackage) -> Bool {
        ecosystemGlobalInstallTargets.contains { target in
            isEcosystemPackageInstalled(package, targetID: target.id)
        }
    }

    func applyAgentsTemplate(to project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }
        do {
            _ = try agentsTemplateService.applyTemplate(
                to: path,
                projectName: project.name,
                sharedBase: agentsSharedBase,
                selectedAdvice: selectedAgentsAdvice
            )
            refreshAgentsProjectAudits()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncInstructionFiles(for project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }
        do {
            _ = try agentsTemplateService.synchronizeInstructionFiles(
                in: path,
                projectName: project.name,
                sharedBase: agentsSharedBase,
                selectedAdvice: selectedAgentsAdvice
            )
            refreshAgentsProjectAudits()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func agentsPreview(for project: ProjectSummary) -> String {
        guard let path = project.path else { return "" }
        let existingURL = URL(fileURLWithPath: path).appendingPathComponent("AGENTS.md")
        let existing = try? String(contentsOf: existingURL, encoding: .utf8)
        return agentsTemplateService.preview(
            projectName: project.name,
            sharedBase: agentsSharedBase,
            selectedAdvice: selectedAgentsAdvice,
            existingContent: existing
        )
    }

    func instructionPreview(for project: ProjectSummary, fileName: String) -> String {
        guard let path = project.path else { return "" }
        let existingURL = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        let existing = try? String(contentsOf: existingURL, encoding: .utf8)
        return agentsTemplateService.preview(
            fileName: fileName,
            projectName: project.name,
            sharedBase: agentsSharedBase,
            selectedAdvice: selectedAgentsAdvice,
            existingContent: existing
        )
    }

    func openInstructionFile(named fileName: String, for project: ProjectSummary) {
        guard let path = project.path else { return }
        let url = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    /// Sends AGENTS.md content to the configured insights API for improvement suggestions.
    func analyzeAgentsMD(content: String, fileName: String = "AGENTS.md") async -> String {
        let systemPrompt = """
        You are an expert at writing \(fileName) instruction files for AI coding agents.

        Review the provided file and return Markdown with exactly these headings:
        ## What works
        ## Suggested improvements
        ## Example edits

        Keep the feedback specific to the file, prefer actionable bullets, and include concrete replacement wording when it would help.
        """

        do {
            let provider = selectedInsightsProvider
            let data = try await callPlainLLM(
                system: systemPrompt,
                userMessage: content,
                provider: provider
            )
            let extracted = AIResponseTextExtractor.extract(from: data, provider: provider)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty {
                return extracted
            }

            let responsePreview = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            runtimeLogger.error(
                "AI analysis returned an empty instruction review",
                metadata: [
                    "file": fileName,
                    "provider": provider.rawValue,
                    "responsePreview": String(responsePreview.prefix(200))
                ]
            )
            return responsePreview.isEmpty
                ? "The AI returned an empty analysis response."
                : "The AI returned a response, but Codebook could not extract the analysis text. Response preview: \(String(responsePreview.prefix(200)))"
        } catch {
            runtimeLogger.error(
                "Failed to analyze instruction file",
                error: error,
                metadata: [
                    "file": fileName,
                    "provider": selectedInsightsProvider.rawValue
                ]
            )
            let message = error.localizedDescription
            if message.hasPrefix("Add a ") || message.hasPrefix("Codebook Free Tier ") || message.hasPrefix("Codebook must be properly signed") {
                return message
            }
            if message == "AI search synthesis failed." {
                return "AI analysis request failed."
            }
            if message.hasPrefix("AI search synthesis failed. ") {
                let details = String(message.dropFirst("AI search synthesis failed. ".count))
                return "AI analysis request failed. \(details)"
            }
            return "Failed to get AI analysis. \(message)"
        }
    }


}
