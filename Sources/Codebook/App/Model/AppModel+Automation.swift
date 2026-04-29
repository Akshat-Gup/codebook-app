import AppKit
import Foundation

extension AppModel {

    func saveSelectedRepoAutomationSettings(_ settings: RepoAutomationSettings) {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = selectedProjectGitRoot else { return }
        repoAutomationStore.save(settings, for: gitRoot)
        refreshSelectedRepoAutomationState()
    }

    func setRepoAutomationTrackedProvider(_ provider: IntegrationProvider, enabled: Bool, for project: ProjectSummary) {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = gitRoot(for: project) else { return }
        var settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
        var providers = Set(settings.trackedProviders)
        if enabled {
            providers.insert(provider)
        } else {
            providers.remove(provider)
        }
        settings.trackedProviders = Array(providers).sorted { $0.rawValue < $1.rawValue }
        repoAutomationStore.save(settings, for: gitRoot)
        refreshSelectedRepoAutomationState()
    }

    func setRepoAutomationExportMode(_ exportMode: RepoAutomationExportMode, for project: ProjectSummary) {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = gitRoot(for: project) else { return }
        var settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
        settings.exportMode = exportMode
        repoAutomationStore.save(settings, for: gitRoot)
        refreshSelectedRepoAutomationState()
    }

    func repoAutomationSettings(for project: ProjectSummary) -> RepoAutomationSettings? {
        guard let path = project.path,
              let gitRoot = promptAutomationService.gitRoot(for: path) else { return nil }
        return repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
    }

    func repoAutomationStatus(for project: ProjectSummary) -> RepoAutomationStatus? {
        guard let path = project.path else { return nil }
        let settings = repoAutomationSettings(for: project) ?? RepoAutomationSettings()
        return promptAutomationService.status(for: path, settings: settings, prompts: importedPrompts)
    }

    func createPromptStore(for project: ProjectSummary) throws -> URL? {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return nil
        }
        guard let path = project.path else { return nil }
        guard let gitRoot = promptAutomationService.gitRoot(for: path) else {
            throw CodebookError.invalidRepository(path)
        }
        let settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
        repoAutomationStore.save(settings, for: gitRoot)
        let url = try promptAutomationService.ensurePromptStoreExists(for: path, settings: settings)
        refreshSelectedRepoAutomationState()
        return url
    }

    func installRepoAutomationHooks(for project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }

        do {
            guard let gitRoot = promptAutomationService.gitRoot(for: path) else {
                throw CodebookError.invalidRepository(path)
            }
            let settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
            repoAutomationStore.save(settings, for: gitRoot)
            _ = try promptAutomationService.installHooks(for: path, settings: settings)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to install Codebook hooks", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func uninstallRepoAutomation(for project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }

        do {
            try promptAutomationService.uninstallHooks(for: path)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to turn off Codebook automation", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func resetPromptStore(for project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }

        do {
            guard let gitRoot = promptAutomationService.gitRoot(for: path) else {
                throw CodebookError.invalidRepository(path)
            }
            let settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
            try promptAutomationService.removePromptStore(for: path, settings: settings)
            repoAutomationStore.remove(for: gitRoot)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to reset prompt store", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func exportPrompts(for project: ProjectSummary) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }

        do {
            guard let gitRoot = promptAutomationService.gitRoot(for: path) else {
                throw CodebookError.invalidRepository(path)
            }
            let settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
            repoAutomationStore.save(settings, for: gitRoot)
            _ = try promptAutomationService.exportPrompts(importedPrompts, to: path, settings: settings)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to export prompts", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func reorganizePromptStore(for project: ProjectSummary, mode: RepoAutomationExportMode) async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let path = project.path else { return }

        do {
            guard let gitRoot = promptAutomationService.gitRoot(for: path) else {
                throw CodebookError.invalidRepository(path)
            }
            var settings = repoAutomationStore.settings(for: gitRoot) ?? RepoAutomationSettings()
            settings.exportMode = mode
            repoAutomationStore.save(settings, for: gitRoot)
            if repoAutomationStatus(for: project)?.hookInstalled == true {
                _ = try promptAutomationService.installHooks(for: path, settings: settings)
            }
            _ = try promptAutomationService.exportPrompts(importedPrompts, to: path, settings: settings)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to reorganize prompt store", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func openPromptStore(for project: ProjectSummary) {
        guard let status = repoAutomationStatus(for: project) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.promptStorePath)])
    }

    func openSelectedRepoPromptStore() {
        guard let project = selectedProjectSummary else { return }
        openPromptStore(for: project)
    }

    func enableSelectedRepoPromptAutomation() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }

        do {
            _ = try createSelectedRepoPromptStore()
            await installSelectedRepoAutomationHooks()
            await exportSelectedRepoPrompts()
            openSelectedRepoPromptStore()
        } catch {
            runtimeLogger.error("Failed to enable repo prompt automation", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func createSelectedRepoPromptStore() throws -> URL? {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return nil
        }
        guard let gitRoot = selectedProjectGitRoot else { return nil }
        let settings = selectedRepoAutomationSettings ?? RepoAutomationSettings()
        let url = try promptAutomationService.ensurePromptStoreExists(for: gitRoot, settings: settings)
        refreshSelectedRepoAutomationState()
        return url
    }

    func installSelectedRepoAutomationHooks() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = selectedProjectGitRoot else { return }
        let settings = selectedRepoAutomationSettings ?? RepoAutomationSettings()
        repoAutomationStore.save(settings, for: gitRoot)

        do {
            _ = try promptAutomationService.installHooks(for: gitRoot, settings: settings)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to install Codebook hooks", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func uninstallSelectedRepoAutomationHooks() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = selectedProjectGitRoot else { return }

        do {
            try promptAutomationService.uninstallHooks(for: gitRoot)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to uninstall Codebook hooks", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func exportSelectedRepoPrompts() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }
        guard let gitRoot = selectedProjectGitRoot else { return }
        let settings = selectedRepoAutomationSettings ?? RepoAutomationSettings()

        do {
            _ = try promptAutomationService.exportPrompts(importedPrompts, to: gitRoot, settings: settings)
            refreshSelectedRepoAutomationState()
        } catch {
            runtimeLogger.error("Failed to export prompts", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func refinePromptText(_ text: String, provider: InsightsProvider) async throws -> String {
        let credentials = try resolveInsightsCredentials(for: provider)
        let transportProvider = credentials.provider
        var request = URLRequest(url: transportProvider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let systemMsg = "You are an expert prompt engineer. Rewrite the user's prompt to be clearer, more specific, and more effective for AI coding tools. Return only the improved prompt text with no explanation."

        let body: [String: Any]
        switch transportProvider.protocolStyle {
        case .openAICompatible:
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": transportProvider.apiFeatureModel,
                "messages": [
                    ["role": "system", "content": systemMsg],
                    ["role": "user", "content": text]
                ],
                "temperature": 0.4
            ]
        case .anthropicMessages:
            request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": transportProvider.defaultModel,
                "max_tokens": 1024,
                "system": systemMsg,
                "messages": [["role": "user", "content": text]]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CodebookError.network("AI refinement request failed.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodebookError.network("Invalid response from AI provider.")
        }


        let extracted = AIResponseTextExtractor.extract(from: json, provider: transportProvider)
        if !extracted.isEmpty {
            return extracted
        }
        throw CodebookError.network("Could not parse AI response.")
    }

    func isGroupExpanded(_ groupID: String) -> Bool {
        expandedGroupIDs.contains(groupID)
    }

    func setGroupExpanded(_ groupID: String, expanded: Bool) {
        if expanded {
            expandedGroupIDs.insert(groupID)
        } else {
            expandedGroupIDs.remove(groupID)
        }
    }

    func isDayExpanded(_ dayID: String) -> Bool {
        expandedDayIDs.contains(dayID)
    }

    func setDayExpanded(_ dayID: String, expanded: Bool) {
        if expanded {
            expandedDayIDs.insert(dayID)
        } else {
            expandedDayIDs.remove(dayID)
        }
    }

    func openDiagnosticsFolder() {
        guard runtimeLogger.isEnabled else { return }
        NSWorkspace.shared.activateFileViewerSelecting([runtimeLogger.logFileURL])
    }

    func openLatestReleasePage() {
        guard let url = appReleasePageURL else { return }
        NSWorkspace.shared.open(url)
    }

    var availableForkProviders: [IntegrationProvider] {
        promptWorkspaceActionService.availableForkTargets()
    }

    func canOpenThread(for prompt: ImportedPrompt) -> Bool {
        isCLIEnabled && promptWorkspaceActionService.canOpenThread(for: prompt)
    }

    func openThread(for prompt: ImportedPrompt) {
        do {
            try promptWorkspaceActionService.openThread(for: prompt)
        } catch {
            runtimeLogger.error("Failed to open prompt thread", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func forkThread(for prompt: ImportedPrompt, to provider: IntegrationProvider) {
        let prompts = promptWorkspaceActionService.threadPrompts(for: prompt, in: importedPrompts)
        let projectPath = prompt.projectPath ?? prompt.gitRoot
        forkPrompts(prompts, projectPath: projectPath, to: provider)
    }

    func forkCommit(_ sha: String, to provider: IntegrationProvider) {
        let prompts = importedPrompts.filter { $0.commitSHA == sha }
        let projectPath = prompts.first?.projectPath ?? prompts.first?.gitRoot
        forkPrompts(prompts, projectPath: projectPath, to: provider)
    }

    func forkPrompts(_ prompts: [ImportedPrompt], projectPath: String?, to provider: IntegrationProvider) {
        do {
            try promptWorkspaceActionService.fork(prompts: prompts, to: provider, projectPath: projectPath)
        } catch {
            runtimeLogger.error("Failed to fork prompts", error: error)
            errorMessage = error.localizedDescription
        }
    }
}
