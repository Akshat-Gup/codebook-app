import Foundation

extension AppModel {

    // MARK: - Search result cache invalidation

    /// Single entry point that recomputes visible results and all grouped search caches.
    func recomputeSearchResults() {
        if let id = selectedProjectID, id.hasPrefix(ImportedPrompt.syntheticProviderProjectKeyPrefix) {
            selectedProjectID = "all-projects"
        }
        let projectFiltered: [ImportedPrompt]
        if let selectedProjectID {
            switch selectedProjectID {
            case "all-projects", "dashboard", "hidden-projects", "ecosystem":
                projectFiltered = importedPrompts
            default:
                projectFiltered = importedPrompts.filter { $0.projectKey == selectedProjectID }
            }
        } else {
            projectFiltered = importedPrompts
        }
        let historyFiltered = applyHistoryFilters(to: projectFiltered.filter(isPromptVisibleInLibrary))

        let newVisible: [ImportedPrompt]
        if searchText.isEmpty {
            newVisible = historyFiltered
        } else {
            let tokens = searchText.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if tokens.isEmpty {
                newVisible = historyFiltered
            } else {
                var scored: [(ImportedPrompt, Double)] = []
                scored.reserveCapacity(historyFiltered.count)
                for prompt in historyFiltered {
                    guard let cache = promptSearchCaches[prompt.id] else { continue }
                    let score = searchScore(for: cache, tokens: tokens)
                    if score > 0 {
                        scored.append((prompt, score))
                    }
                }
                newVisible = scored.sorted { $0.1 > $1.1 }.map { $0.0 }
            }
        }

        visiblePrompts = newVisible
        dayGroups = Self.buildDayGroups(from: newVisible, groupingMode: historyGroupingMode)

        searchTabCounts = buildSearchTabCounts(from: newVisible)
        searchResultsRevision &+= 1
        resetSearchTabCaches()
        loadSearchTabIfNeeded(searchTab)
    }

    func preserveSelection() {
        if isDashboardSelected {
            selectedPromptID = nil
            return
        }
        if isInsightsSelected {
            selectedPromptID = nil
            return
        }
        if isSavedSelected {
            selectedPromptID = preferredSavedPromptID
            return
        }
        if isHiddenProjectsSelected {
            selectedPromptID = preferredHiddenPromptID
            return
        }
        if isAutomationsSelected {
            selectedPromptID = nil
            return
        }
        if isEcosystemSelected {
            selectedPromptID = nil
            return
        }
        if selectedProjectID == nil {
            selectedProjectID = projectSummaries.first?.id
        }
        if let selectedPromptID, visiblePrompts.contains(where: { $0.id == selectedPromptID }) {
            return
        }
        self.selectedPromptID = visiblePrompts.first?.id
    }

    func applySearchText(_ newSearchText: String) {
        if !newSearchText.isEmpty &&
            (isDashboardSelected || isInsightsSelected || isSavedSelected || isHiddenProjectsSelected || isAutomationsSelected || isEcosystemSelected) {
            selectedProjectID = "all-projects"
        }
        if newSearchText.isEmpty {
            searchTab = .all
            aiSearchResults = []
            aiSearchQuery = nil
            aiSearchError = nil
            aiSearchReasoning = nil
            aiSearchSummary = nil
            aiSearchTask?.cancel()
            aiSearchIsRunning = false
        }
        searchText = newSearchText
        recomputeSearchResults()
        preserveSelection()
    }

    func historyFiltersDidChange() {
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        preserveSelection()
    }

    func applyHistoryFilters(to prompts: [ImportedPrompt]) -> [ImportedPrompt] {
        guard hasActiveHistoryFilters else { return prompts }
        return prompts.filter { prompt in
            if let platform = historyFilterPlatform, prompt.provider != platform {
                return false
            }

            if let start = historyFilterStartDate, prompt.effectiveDate < start {
                return false
            }

            if let end = historyFilterEndDate, prompt.effectiveDate > end {
                return false
            }

            return true
        }
    }

    func searchScore(for prompt: PromptSearchCache, tokens: [String]) -> Double {
        var totalScore: Double = 0

        for token in tokens {
            var tokenScore: Double = 0

            if prompt.title.contains(token) { tokenScore += 10 }
            if prompt.tags.contains(token) { tokenScore += 8 }
            if prompt.project.contains(token) { tokenScore += 6 }
            if prompt.provider.contains(token) { tokenScore += 5 }
            if prompt.commit.contains(token) { tokenScore += 4 }
            if prompt.body.contains(token) { tokenScore += 2 }

            if prompt.title.hasPrefix(token) { tokenScore += 5 }

            if tokenScore == 0 {
                if fuzzyMatch(token, in: prompt.title) { tokenScore += 3 }
                else if fuzzyMatch(token, in: prompt.tags) { tokenScore += 2 }
                else if fuzzyMatch(token, in: prompt.project) { tokenScore += 1.5 }
                else if fuzzyMatch(token, in: prompt.commit) { tokenScore += 1 }
                else if fuzzyMatch(token, in: prompt.body) { tokenScore += 0.5 }
            }

            if tokenScore == 0 { return 0 }
            totalScore += tokenScore
        }

        return totalScore
    }

    func fuzzyMatch(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count >= 2 else { return haystack.contains(needle) }
        var needleIndex = needle.startIndex
        for char in haystack {
            if char == needle[needleIndex] {
                needleIndex = needle.index(after: needleIndex)
                if needleIndex == needle.endIndex { return true }
            }
        }
        return false
    }

    func rebuildPromptSearchCaches() {
        promptByID = Dictionary(uniqueKeysWithValues: importedPrompts.map { ($0.id, $0) })
        promptSearchCaches = Dictionary(uniqueKeysWithValues: importedPrompts.map { prompt in
            (prompt.id, PromptSearchCache(prompt: prompt))
        })
    }

    func applyScanProgress(_ progress: IntegrationScanProgress) {
        let totalProviders = max(progress.totalProviders, 1)
        let completedFraction = Double(progress.completedProviders) / Double(totalProviders)
        loadingProgress = min(0.08 + completedFraction * 0.78, 0.9)

        if let provider = progress.latestProvider {
            loadingStatusText = "Loaded \(provider.title) (\(progress.completedProviders)/\(progress.totalProviders))"
            if stagesPartialScanResults {
                stagedScanPromptsByProvider[provider] = progress.latestPrompts
                applyStagedScanPrompts()
            }
        } else {
            loadingStatusText = "Scanning prompt history…"
        }
    }

    func applyStagedScanPrompts() {
        let merged = deduplicateStagedPrompts(stagedScanPromptsByProvider.values.flatMap { $0 })
        guard !merged.isEmpty else { return }

        importedPrompts = merged
        importedPromptsRevision &+= 1
        rebuildPromptSearchCaches()
        rebuildDerivedPromptCaches()
        recomputeSearchResults()
        normalizeLocalChangesProjectSelection()
        refreshSelectedRepoAutomationState()
        preserveSelection()
    }

    func deduplicateStagedPrompts(_ prompts: [ImportedPrompt]) -> [ImportedPrompt] {
        var seen = Set<String>()
        return prompts
            .filter { seen.insert($0.stableLibraryKey).inserted }
            .sorted { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.id > rhs.id
                }
                return lhs.capturedAt > rhs.capturedAt
            }
    }

    func rebuildDerivedPromptCaches() {
        var visiblePromptCount = 0
        var minimumEffectiveDate: Date?
        var maximumEffectiveDate: Date?
        var savedCommitPromptIDs = Set<String>()
        savedCommitPromptIDs.reserveCapacity(savedCommitSHAs.count)
        var visibleProjectMap: [String: (name: String, path: String?, count: Int)] = [:]

        for prompt in importedPrompts {
            guard isPromptVisibleInLibrary(prompt) else { continue }
            visiblePromptCount += 1
            if let current = visibleProjectMap[prompt.projectKey] {
                visibleProjectMap[prompt.projectKey] = (current.name, current.path, current.count + 1)
            } else {
                visibleProjectMap[prompt.projectKey] = (prompt.projectName, prompt.gitRoot ?? prompt.projectPath, 1)
            }

            let effectiveDate = prompt.effectiveDate
            if let currentMinimum = minimumEffectiveDate {
                if effectiveDate < currentMinimum {
                    minimumEffectiveDate = effectiveDate
                }
            } else {
                minimumEffectiveDate = effectiveDate
            }

            if let currentMaximum = maximumEffectiveDate {
                if effectiveDate > currentMaximum {
                    maximumEffectiveDate = effectiveDate
                }
            } else {
                maximumEffectiveDate = effectiveDate
            }

            if let sha = prompt.commitSHA, savedCommitSHAs.contains(sha) {
                savedCommitPromptIDs.insert(prompt.id)
            }
        }

        let visibleProjects = visibleProjectMap.map { key, value in
            ProjectSummary(id: key, name: value.name, path: value.path, promptCount: value.count, isManual: manualFolders.contains(key))
        }
            .filter { !$0.id.hasPrefix(ImportedPrompt.syntheticProviderProjectKeyPrefix) }
            .sorted { lhs, rhs in
                let lhsPinned = pinnedProjectIDs.contains(lhs.id)
                let rhsPinned = pinnedProjectIDs.contains(rhs.id)
                if lhsPinned != rhsPinned {
                    return lhsPinned && !rhsPinned
                }
                if lhs.promptCount == rhs.promptCount {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.promptCount > rhs.promptCount
            }

        projectSummariesCache = [
            ProjectSummary(id: "all-projects", name: "All Projects", path: nil, promptCount: visiblePromptCount, isManual: false)
        ] + visibleProjects
        pinnedProjectSummariesCache = visibleProjects.filter { pinnedProjectIDs.contains($0.id) }
        otherProjectSummariesCache = projectSummariesCache.filter { $0.id == "all-projects" || !pinnedProjectIDs.contains($0.id) }

        let explicitlySavedPromptIDs = Set(
            importedPrompts.compactMap { prompt in
                savedPromptKeys.contains(prompt.stableLibraryKey) ? prompt.id : nil
            }
        )
        let includedPromptIDs = explicitlySavedPromptIDs.union(savedCommitPromptIDs)
        let filteredSavedPrompts = applyHistoryFilters(
            to: importedPrompts
                .filter { includedPromptIDs.contains($0.id) && isPromptVisibleInLibrary($0) }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.effectiveDate
                    let rhsDate = rhs.effectiveDate
                    if lhsDate == rhsDate {
                        return lhs.capturedAt > rhs.capturedAt
                    }
                    return lhsDate > rhsDate
                }
        )

        savedPromptsCache = filteredSavedPrompts.filter { explicitlySavedPromptIDs.contains($0.id) }
        savedVisiblePromptsCache = filteredSavedPrompts
        savedCommitGroupsCache = Self.buildSavedCommitGroups(
            from: importedPrompts.filter(isPromptVisibleInLibrary),
            savedCommitSHAs: savedCommitSHAs
        )
        savedDayGroupsCache = Self.buildDayGroups(from: filteredSavedPrompts, groupingMode: historyGroupingMode)

        let hiddenProjects = allProjects
            .filter { hiddenProjectIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hiddenProjectsCache = hiddenProjects

        let localChangesProjectIDs = Set(
            importedPrompts.compactMap { prompt in
                prompt.gitRoot == nil ? nil : prompt.projectKey
            }
        ).union(manualFolders)
        // Keep cache rebuilds cheap; local-changes analysis validates git state when it runs.
        let localChangesProjects = projectSummariesCache.filter { project in
            guard project.id != "all-projects", project.path != nil else { return false }
            return localChangesProjectIDs.contains(project.id)
        }
        localChangesProjectOptionsCache = localChangesProjects
        automationProjectsCache = localChangesProjects.sorted { lhs, rhs in
            let lhsPinned = pinnedProjectIDs.contains(lhs.id)
            let rhsPinned = pinnedProjectIDs.contains(rhs.id)
            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let baseHiddenPromptList = importedPrompts
            .filter { hiddenPromptKeys.contains($0.stableLibraryKey) }
            .sorted { lhs, rhs in
                if lhs.capturedAt == rhs.capturedAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.capturedAt > rhs.capturedAt
            }
        hiddenPromptsCache = baseHiddenPromptList

        hiddenVisiblePromptsCache = applyHistoryFilters(to: baseHiddenPromptList)
        hiddenPromptGroupsCache = Self.buildPromptGroups(from: hiddenVisiblePromptsCache, groupingMode: historyGroupingMode)
        sessionDayGroupsCache = Self.buildSessionDayGroups(
            from: importedPrompts,
            canResume: { canOpenThread(for: $0) }
        )

        if let minimumEffectiveDate, let maximumEffectiveDate {
            historyFilterDateBoundsCache = minimumEffectiveDate ... maximumEffectiveDate
        } else {
            historyFilterDateBoundsCache = nil
        }
    }

    func resetSearchTabCaches() {
        searchTabLoadTask?.cancel()
        searchTabLoading = nil
        loadedSearchTabs = []
        searchByCommits = []
        searchByDates = []
        searchByProjects = []
        searchByTags = []
        searchByProviders = []
    }

    func loadSearchTabIfNeeded(_ tab: SearchTab) {
        guard !searchText.isEmpty else {
            searchTabLoading = nil
            return
        }
        guard tab != .all else {
            searchTabLoading = nil
            return
        }
        guard !loadedSearchTabs.contains(tab) else {
            searchTabLoading = nil
            return
        }

        searchTabLoadTask?.cancel()
        searchTabLoading = tab

        let revision = searchResultsRevision
        let prompts = visiblePrompts
        searchTabLoadTask = Task.detached { [weak self, revision, tab, prompts] in
            let payload = Self.buildSearchTabPayload(tab: tab, prompts: prompts)
            guard !Task.isCancelled else { return }
            await self?.applySearchTabPayload(payload, for: tab, revision: revision)
        }
    }

    func applySearchTabPayload(_ payload: SearchTabPayload, for tab: SearchTab, revision: Int) {
        guard revision == searchResultsRevision else { return }

        switch payload {
        case .commits(let groups):
            searchByCommits = groups
        case .dates(let groups):
            searchByDates = groups
        case .projects(let groups):
            searchByProjects = groups
        case .tags(let groups):
            searchByTags = groups
        case .providers(let groups):
            searchByProviders = groups
        case .all:
            break
        }

        loadedSearchTabs.insert(tab)
        if searchTab == tab {
            searchTabLoading = nil
        }
    }

    nonisolated static func buildSearchTabPayload(tab: SearchTab, prompts: [ImportedPrompt]) -> SearchTabPayload {
        switch tab {
        case .all:
            return .all
        case .commits:
            return .commits(buildSearchByCommits(from: prompts))
        case .dates:
            return .dates(buildSearchByDates(from: prompts))
        case .projects:
            return .projects(buildSearchByProjects(from: prompts))
        case .tags:
            return .tags(buildSearchByTags(from: prompts))
        case .providers:
            return .providers(buildSearchByProviders(from: prompts))
        }
    }

    nonisolated static func buildSearchByCommits(from prompts: [ImportedPrompt]) -> [SearchCommitGroup] {
        let withCommit = Dictionary(grouping: prompts.filter { $0.commitSHA != nil }) { $0.commitSHA! }
        var groups = withCommit.map { sha, items in
            SearchCommitGroup(
                key: sha,
                message: items.first?.commitMessage ?? String(sha.prefix(7)),
                sha: sha,
                prompts: items.sorted { $0.capturedAt > $1.capturedAt }
            )
        }
        .sorted { lhs, rhs in
            if lhs.prompts.count == rhs.prompts.count {
                return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
            }
            return lhs.prompts.count > rhs.prompts.count
        }

        let unlinked = prompts.filter { $0.commitSHA == nil }.sorted { $0.capturedAt > $1.capturedAt }
        if !unlinked.isEmpty {
            groups.append(SearchCommitGroup(key: "no-commit", message: "No linked commit", sha: nil, prompts: unlinked))
        }

        return groups
    }

    nonisolated static func buildSearchByDates(from prompts: [ImportedPrompt]) -> [SearchDateGroup] {
        let groupedByDay = Dictionary(grouping: prompts) { prompt in
            dayKey(for: prompt.commitDate ?? prompt.capturedAt)
        }
        return groupedByDay.compactMap { key, items -> SearchDateGroup? in
            guard let ref = items.first else { return nil }
            let date = ref.commitDate ?? ref.capturedAt
            return SearchDateGroup(
                key: key,
                title: displayDayString(for: date),
                date: date,
                prompts: items.sorted { $0.capturedAt > $1.capturedAt }
            )
        }
        .sorted { $0.date > $1.date }
    }

    nonisolated static func buildSearchByProjects(from prompts: [ImportedPrompt]) -> [SearchProjectGroup] {
        Dictionary(grouping: prompts) { $0.projectKey }
            .map { key, items in
                SearchProjectGroup(
                    key: key,
                    name: items.first?.projectName ?? key,
                    prompts: items.sorted { $0.capturedAt > $1.capturedAt }
                )
            }
            .sorted { lhs, rhs in
                if lhs.prompts.count == rhs.prompts.count {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.prompts.count > rhs.prompts.count
            }
    }

    nonisolated static func buildSearchByTags(from prompts: [ImportedPrompt]) -> [SearchTagGroup] {
        var tagMap: [String: [ImportedPrompt]] = [:]
        for prompt in prompts {
            for tag in prompt.tags {
                tagMap[tag, default: []].append(prompt)
            }
        }

        var groups = tagMap.map { tag, items in
            SearchTagGroup(tag: tag, prompts: items.sorted { $0.capturedAt > $1.capturedAt })
        }
        .sorted { lhs, rhs in
            if lhs.prompts.count == rhs.prompts.count {
                return lhs.tag.localizedCaseInsensitiveCompare(rhs.tag) == .orderedAscending
            }
            return lhs.prompts.count > rhs.prompts.count
        }

        let untagged = prompts.filter { $0.tags.isEmpty }.sorted { $0.capturedAt > $1.capturedAt }
        if !untagged.isEmpty {
            groups.append(SearchTagGroup(tag: "Untagged", prompts: untagged))
        }

        return groups
    }

    nonisolated static func buildSearchByProviders(from prompts: [ImportedPrompt]) -> [SearchProviderGroup] {
        let byProvider = Dictionary(grouping: prompts) { $0.provider }
        return IntegrationProvider.allCases.compactMap { provider in
            guard let items = byProvider[provider], !items.isEmpty else { return nil }
            return SearchProviderGroup(provider: provider, prompts: items.sorted { $0.capturedAt > $1.capturedAt })
        }
    }

    func buildSearchTabCounts(from prompts: [ImportedPrompt]) -> [SearchTab: Int] {
        guard !searchText.isEmpty else { return [:] }

        var commitKeys = Set<String>()
        var dayKeys = Set<String>()
        var projectKeys = Set<String>()
        var tagKeys = Set<String>()
        var providerKeys = Set<IntegrationProvider>()
        var hasUnlinkedCommit = false
        var hasUntagged = false

        for prompt in prompts {
            if let sha = prompt.commitSHA {
                commitKeys.insert(sha)
            } else {
                hasUnlinkedCommit = true
            }
            dayKeys.insert(Self.dayKey(for: prompt.commitDate ?? prompt.capturedAt))
            projectKeys.insert(prompt.projectKey)
            if prompt.tags.isEmpty {
                hasUntagged = true
            } else {
                for tag in prompt.tags {
                    tagKeys.insert(tag)
                }
            }
            providerKeys.insert(prompt.provider)
        }

        return [
            .all: prompts.count,
            .commits: commitKeys.count + (hasUnlinkedCommit ? 1 : 0),
            .dates: dayKeys.count,
            .projects: projectKeys.count,
            .tags: tagKeys.count + (hasUntagged ? 1 : 0),
            .providers: providerKeys.count
        ]
    }

    nonisolated static func buildDayGroups(
        from prompts: [ImportedPrompt],
        groupingMode: HistoryGroupingMode
    ) -> [DayPromptGroup] {
        let groupedByDay = Dictionary(grouping: prompts) { prompt in
            dayKey(for: prompt.commitDate ?? prompt.capturedAt)
        }

        return groupedByDay.compactMap { key, items -> DayPromptGroup? in
            guard let first = items.max(by: { ($0.commitDate ?? $0.capturedAt) < ($1.commitDate ?? $1.capturedAt) }) else { return nil }
            var groups = buildPromptGroups(from: items, groupingMode: groupingMode)
            groups.sort { $0.date > $1.date }
            return DayPromptGroup(
                id: "day-\(key)",
                title: displayDayString(for: first.commitDate ?? first.capturedAt),
                date: first.commitDate ?? first.capturedAt,
                groups: groups
            )
        }
        .sorted { $0.date > $1.date }
    }

    nonisolated static func buildPromptGroups(
        from prompts: [ImportedPrompt],
        groupingMode: HistoryGroupingMode
    ) -> [PromptGroup] {
        switch groupingMode {
        case .commit:
            let structured = Dictionary(grouping: prompts.filter { $0.commitSHA != nil }) { $0.commitSHA ?? "" }
            let unstructured = prompts.filter { $0.commitSHA == nil }

            var groups: [PromptGroup] = structured.compactMap { sha, groupedItems in
                let sortedItems = groupedItems.sorted { $0.capturedAt > $1.capturedAt }
                guard let lead = sortedItems.first else { return nil }
                return PromptGroup(
                    id: "commit-\(sha)",
                    title: lead.commitMessage?.isEmpty == false ? lead.commitMessage! : String(sha.prefix(7)),
                    subtitle: lead.commitSubtitleLabel,
                    prompts: sortedItems,
                    date: lead.commitDate ?? lead.capturedAt,
                    structured: true,
                    kind: .commit
                )
            }

            for prompt in unstructured {
                groups.append(
                    PromptGroup(
                        id: "prompt-\(prompt.id)",
                        title: prompt.title,
                        subtitle: nil,
                        prompts: [prompt],
                        date: prompt.capturedAt,
                        structured: false,
                        kind: .single
                    )
                )
            }
            return groups

        case .thread:
            return Dictionary(grouping: prompts, by: PromptThreading.key(for:))
                .compactMap { threadKey, groupedItems in
                    let sortedItems = groupedItems.sorted { $0.capturedAt > $1.capturedAt }
                    guard let lead = sortedItems.first else { return nil }
                    if sortedItems.count == 1 {
                        return PromptGroup(
                            id: "prompt-\(lead.id)",
                            title: lead.title,
                            subtitle: nil,
                            prompts: sortedItems,
                            date: lead.effectiveDate,
                            structured: false,
                            kind: .single
                        )
                    }

                    return PromptGroup(
                        id: "thread-\(threadKey)",
                        title: lead.title,
                        subtitle: "\(sortedItems.count) prompts",
                        prompts: sortedItems,
                        date: lead.effectiveDate,
                        structured: true,
                        kind: .thread
                    )
                }
        }
    }

    var currentWorkspacePath: String? {
        projectSummaries.first(where: { $0.id == selectedProjectID })?.path
    }

    var selectedProjectGitRoot: String? {
        guard let workspacePath = currentWorkspacePath else { return nil }
        return promptAutomationService.gitRoot(for: workspacePath)
    }

    func gitRoot(for project: ProjectSummary) -> String? {
        guard let path = project.path else { return nil }
        return promptAutomationService.gitRoot(for: path)
    }

    func requireGitRoot(for project: ProjectSummary) throws -> String {
        guard let path = project.path,
              let gitRoot = promptAutomationService.gitRoot(for: path) else {
            throw CodebookError.invalidRepository(project.name)
        }
        return gitRoot
    }

    func refreshSelectedRepoAutomationState() {
        guard let gitRoot = selectedProjectGitRoot else {
            selectedRepoAutomationSettings = nil
            selectedRepoAutomationStatus = nil
            return
        }

        let settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
        selectedRepoAutomationSettings = settings
        selectedRepoAutomationStatus = promptAutomationService.status(
            for: gitRoot,
            settings: settings,
            prompts: importedPrompts
        )
    }

    func refreshEcosystemSnapshots() {
        ecosystemSnapshots = ecosystemInstallTargets.map { ecosystemWorkspaceService.snapshot(for: $0) }
        ecosystemDiscoveredInstalledPackages = ecosystemWorkspaceService.discoverInstalledPackages(
            targets: ecosystemInstallTargets.filter(\.isBuiltIn)
        )
        normalizeEcosystemInstallTargetSelection()
    }

    func normalizeEcosystemInstallTargetSelection() {
        let valid = Set(ecosystemInstallTargets.map(\.id))
        var next = ecosystemInstallTargetSelection.intersection(valid)
        if next.isEmpty {
            next = valid
        } else if let previous = lastEcosystemValidInstallTargetIDs {
            next.formUnion(valid.subtracting(previous))
        }
        lastEcosystemValidInstallTargetIDs = valid
        if next != ecosystemInstallTargetSelection {
            ecosystemInstallTargetSelection = next
            persist(Array(next).sorted(), forKey: ecosystemInstallTargetIDsKey)
        }
    }

    func refreshAgentsProjectAudits() {
        agentsProjectAudits = agentsTemplateService.auditProjects(
            agentsProjects,
            sharedBase: agentsSharedBase,
            selectedAdvice: selectedAgentsAdvice
        )
    }

    func syncConfiguredRepoAutomationsIfNeeded(prompts: [ImportedPrompt]) {
        guard !runtimePolicy.readOnly else { return }
        let settingsByGitRoot = repoAutomationStore.allSettings()
        guard !settingsByGitRoot.isEmpty else { return }

        Task.detached(priority: .utility) { [prompts, settingsByGitRoot] in
            do {
                _ = try PromptAutomationService().syncConfiguredRepositories(
                    prompts: prompts,
                    settingsByGitRoot: settingsByGitRoot
                )
            } catch {
                RuntimeLogger.shared.error("Failed to sync prompt exports", error: error)
            }
        }
    }

    func persist(_ value: Any?, forKey key: String) {
        guard runtimePolicy.persistentStorageEnabled else { return }
        defaults.set(value, forKey: key)
    }

    func syncSavedPromptIDs() {
        guard !importedPrompts.isEmpty else { return }
        savedPromptIDs = Set(
            importedPrompts.compactMap { prompt in
                savedPromptKeys.contains(prompt.stableLibraryKey) ? prompt.id : nil
            }
        )
        persist(Array(savedPromptIDs).sorted(), forKey: savedPromptIDsKey)
    }

    func persistCustomProviderProfiles() {
        guard runtimePolicy.persistentStorageEnabled else { return }
        guard let data = try? JSONEncoder().encode(customProviderProfiles) else { return }
        defaults.set(data, forKey: customProviderProfilesKey)
    }

    func normalizeLocalChangesProjectSelection() {
        let options = localChangesProjectOptions
        guard !options.isEmpty else {
            if localChangesProjectID != nil {
                localChangesProjectID = nil
                persist(nil as String?, forKey: localChangesProjectIDKey)
            }
            return
        }

        if let selected = localChangesProjectID,
           options.contains(where: { $0.id == selected }) {
            return
        }

        let fallback = options.first?.id
        localChangesProjectID = fallback
        persist(fallback, forKey: localChangesProjectIDKey)
    }

    func normalizeSavedState() {
        syncSavedPromptIDs()
        persist(Array(savedPromptKeys).sorted(), forKey: savedPromptKeysKey)
        persist(Array(savedCommitSHAs).sorted(), forKey: savedCommitSHAsKey)
        persist(Array(hiddenPromptKeys).sorted(), forKey: hiddenPromptKeysKey)

        let strippedPins = pinnedProjectIDs.filter { !$0.hasPrefix(ImportedPrompt.syntheticProviderProjectKeyPrefix) }
        if strippedPins.count != pinnedProjectIDs.count {
            pinnedProjectIDs = strippedPins
            persist(Array(pinnedProjectIDs).sorted(), forKey: pinnedProjectsKey)
        }
    }

    var preferredSavedPromptID: String? {
        if let selectedPromptID,
           let selectedPrompt = promptByID[selectedPromptID] {
            if savedPromptKeys.contains(selectedPrompt.stableLibraryKey) {
                return selectedPromptID
            }
            if let sha = selectedPrompt.commitSHA, savedCommitSHAs.contains(sha) {
                return selectedPromptID
            }
        }

        if let savedPromptID = savedVisiblePrompts.first?.id {
            return savedPromptID
        }
        
        return nil
    }

    var preferredHiddenPromptID: String? {
        if let selectedPromptID,
           hiddenVisiblePrompts.contains(where: { $0.id == selectedPromptID }) {
            return selectedPromptID
        }
        return hiddenVisiblePrompts.first?.id
    }

    var visiblePromptCount: Int {
        projectSummariesCache.first?.promptCount ?? 0
    }

    func isPromptVisibleInLibrary(_ prompt: ImportedPrompt) -> Bool {
        !hiddenProjectIDs.contains(prompt.projectKey) && !hiddenPromptKeys.contains(prompt.stableLibraryKey)
    }

    func migrateLegacyPromptStateIfNeeded() {
        guard !importedPrompts.isEmpty else { return }
        let legacySavedPromptIDs = Set(defaults.stringArray(forKey: savedPromptIDsKey) ?? [])
        let legacySavedKeys = savedPromptKeys.filter(ImportedPrompt.usesLegacyLibraryKeyFormat)
        if !legacySavedPromptIDs.isEmpty || !legacySavedKeys.isEmpty {
            var nextSavedKeys = savedPromptKeys.subtracting(legacySavedKeys)
            nextSavedKeys.formUnion(
                importedPrompts.compactMap { prompt in
                    if legacySavedPromptIDs.contains(prompt.id) || legacySavedKeys.contains(prompt.legacyLibraryKey) {
                        return prompt.stableLibraryKey
                    }
                    return nil
                }
            )
            if nextSavedKeys != savedPromptKeys {
                savedPromptKeys = nextSavedKeys
                persist(Array(savedPromptKeys).sorted(), forKey: savedPromptKeysKey)
            }
        }

        let legacyHiddenPromptIDs = Set(defaults.stringArray(forKey: legacyHiddenPromptIDsKey) ?? [])
        let legacyHiddenKeys = hiddenPromptKeys.filter(ImportedPrompt.usesLegacyLibraryKeyFormat)
        if !legacyHiddenPromptIDs.isEmpty || !legacyHiddenKeys.isEmpty {
            var nextHiddenKeys = hiddenPromptKeys.subtracting(legacyHiddenKeys)
            nextHiddenKeys.formUnion(
                importedPrompts.compactMap { prompt in
                    if legacyHiddenPromptIDs.contains(prompt.id) || legacyHiddenKeys.contains(prompt.legacyLibraryKey) {
                        return prompt.stableLibraryKey
                    }
                    return nil
                }
            )
            if nextHiddenKeys != hiddenPromptKeys {
                hiddenPromptKeys = nextHiddenKeys
                persist(Array(hiddenPromptKeys).sorted(), forKey: hiddenPromptKeysKey)
            }
        }
    }

    var allProjects: [ProjectSummary] {
        var map: [String: (name: String, path: String?, count: Int)] = [:]
        let manualFolderSet = Set(manualFolders)
        for prompt in importedPrompts {
            if let current = map[prompt.projectKey] {
                map[prompt.projectKey] = (current.name, current.path, current.count + 1)
            } else {
                map[prompt.projectKey] = (prompt.projectName, prompt.gitRoot ?? prompt.projectPath, 1)
            }
        }
        for folder in manualFolders {
            let name = URL(fileURLWithPath: folder).lastPathComponent
            map[folder] = map[folder] ?? (name.isEmpty ? folder : name, folder, 0)
        }
        return map.map {
            ProjectSummary(id: $0.key, name: $0.value.name, path: $0.value.path, promptCount: $0.value.count, isManual: manualFolderSet.contains($0.key))
        }
    }

    nonisolated static func buildSavedCommitGroups(
        from prompts: [ImportedPrompt],
        savedCommitSHAs: Set<String>
    ) -> [SearchCommitGroup] {
        var grouped: [String: [ImportedPrompt]] = [:]
        for prompt in prompts {
            guard let sha = prompt.commitSHA, savedCommitSHAs.contains(sha) else { continue }
            grouped[sha, default: []].append(prompt)
        }

        return grouped.compactMap { sha, items in
            guard !sha.isEmpty else { return nil }
            return SearchCommitGroup(
                key: sha,
                message: items.first?.commitMessage ?? String(sha.prefix(7)),
                sha: sha,
                prompts: items.sorted { $0.capturedAt > $1.capturedAt }
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.prompts.first?.commitDate ?? lhs.prompts.first?.capturedAt ?? .distantPast
            let rhsDate = rhs.prompts.first?.commitDate ?? rhs.prompts.first?.capturedAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
            }
            return lhsDate > rhsDate
        }
    }

    nonisolated static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    nonisolated static func endOfDay(for date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    nonisolated static func displayDayString(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct PromptSearchCache {
    let title: String
    let body: String
    let tags: String
    let project: String
    let provider: String
    let commit: String

    init(prompt: ImportedPrompt) {
        self.title = prompt.title.lowercased()
        self.body = prompt.body.lowercased()
        self.tags = prompt.tags.joined(separator: " ").lowercased()
        self.project = prompt.projectName.lowercased()
        self.provider = prompt.provider.title.lowercased()
        self.commit = (prompt.commitMessage ?? "").lowercased()
    }
}

actor ScanProgressRelay {
    private let handler: @MainActor (IntegrationScanProgress) -> Void

    init(handler: @escaping @MainActor (IntegrationScanProgress) -> Void) {
        self.handler = handler
    }

    func report(_ progress: IntegrationScanProgress) async {
        await handler(progress)
    }
}

enum SearchTabPayload {
    case all
    case commits([SearchCommitGroup])
    case dates([SearchDateGroup])
    case projects([SearchProjectGroup])
    case tags([SearchTagGroup])
    case providers([SearchProviderGroup])
}
