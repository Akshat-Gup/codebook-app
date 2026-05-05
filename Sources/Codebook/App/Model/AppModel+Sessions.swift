import Foundation

enum HarnessSessionMode: String, CaseIterable, Hashable {
    case agentSessions
    case oneHour
    case overnight
    case oneDay
    case custom
    case indefinite

    var title: String {
        switch self {
        case .agentSessions: return "Agent sessions"
        case .oneHour: return "1 hour"
        case .overnight: return "Overnight"
        case .oneDay: return "1 day"
        case .custom: return "Custom"
        case .indefinite: return "Until turned off"
        }
    }

    var systemImage: String {
        switch self {
        case .agentSessions: return "terminal"
        case .oneHour: return "clock"
        case .overnight: return "moon.stars"
        case .oneDay: return "sun.max"
        case .custom: return "slider.horizontal.3"
        case .indefinite: return "infinity"
        }
    }

    var durationSeconds: Int? {
        switch self {
        case .agentSessions: return nil
        case .oneHour: return 60 * 60
        case .overnight: return 10 * 60 * 60
        case .oneDay: return 24 * 60 * 60
        case .custom: return nil
        case .indefinite: return nil
        }
    }
}

extension AppModel {
    static func buildSessionDayGroups(
        from prompts: [ImportedPrompt],
        canResume: (ImportedPrompt) -> Bool
    ) -> [SessionDayGroup] {
        let sessions = Dictionary(grouping: prompts, by: sessionKey(for:))
            .values
            .map { prompts in
                let sorted = prompts.sorted { $0.capturedAt < $1.capturedAt }
                let first = sorted[0]
                let latest = sorted.last ?? first
                return SessionSummary(
                    id: sessionKey(for: first),
                    projectID: first.projectKey,
                    projectName: first.projectName,
                    provider: first.provider,
                    title: latest.title.isEmpty ? first.provider.title : latest.title,
                    prompts: sorted,
                    startedAt: first.capturedAt,
                    lastActiveAt: latest.capturedAt,
                    duration: max(latest.capturedAt.timeIntervalSince(first.capturedAt), 0),
                    commitCount: Set(sorted.compactMap(\.commitSHA)).count,
                    canResume: canResume(latest)
                )
            }

        return Dictionary(grouping: sessions) { session in
            Calendar.current.startOfDay(for: session.lastActiveAt)
        }
            .values
            .map { daySessions in
                let sorted = daySessions.sorted { $0.lastActiveAt > $1.lastActiveAt }
                let first = sorted[0]
                let day = Calendar.current.startOfDay(for: first.lastActiveAt)
                return SessionDayGroup(
                    id: "sessions-\(Int(day.timeIntervalSince1970))",
                    title: sessionDayTitle(for: day),
                    date: day,
                    sessions: sorted,
                    lastActiveAt: sorted.map(\.lastActiveAt).max() ?? first.lastActiveAt
                )
            }
            .sorted { $0.date > $1.date }
    }

    static func sessionKey(for prompt: ImportedPrompt) -> String {
        let context = prompt.sourceContextID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context, !context.isEmpty {
            return "\(prompt.provider.rawValue)|\(prompt.projectKey)|\(context)"
        }
        return "\(prompt.provider.rawValue)|\(prompt.projectKey)|\(prompt.sourcePath)"
    }

    static func sessionDayTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    func refreshHarnessSessionStatus() {
        // Shell.run calls (launchctl list, pgrep ×N) block — run them off the
        // main thread so we don't stutter during the 5-second polling loop.
        let homeDirectory = harnessSessionService.homeDirectory
        let label = harnessSessionService.label
        let names = Array(enabledHarnessProcessNames)
        harnessStatusRefreshTask?.cancel()
        harnessStatusRefreshTask = Task {
            let newStatus: HarnessSessionStatus = await Task.detached(priority: .utility) {
                let service = HarnessSessionService(homeDirectory: homeDirectory, label: label)
                return service.status(processNames: names)
            }.value
            guard !Task.isCancelled else { return }
            harnessSessionStatus = newStatus
        }
    }

    func installHarnessSessionWatcher() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }

        let homeDirectory = harnessSessionService.homeDirectory
        let label = harnessSessionService.label
        let processNames = Array(enabledHarnessProcessNames)
        let pollIntervalSeconds = harnessPollIntervalSeconds
        let mode = harnessMode
        let customDurationSeconds = harnessCustomDurationSeconds
        let keepDisplayAwake = harnessKeepDisplayAwake
        let powerAdapterOnly = harnessPowerAdapterOnly

        do {
            try await Task.detached(priority: .utility) {
                let service = HarnessSessionService(homeDirectory: homeDirectory, label: label)
                try service.install(
                    processNames: processNames,
                    pollIntervalSeconds: pollIntervalSeconds,
                    mode: mode,
                    customDurationSeconds: customDurationSeconds,
                    keepDisplayAwake: keepDisplayAwake,
                    powerAdapterOnly: powerAdapterOnly
                )
            }.value
            refreshHarnessSessionStatus()
        } catch {
            runtimeLogger.error("Failed to start session watcher", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func uninstallHarnessSessionWatcher() async {
        guard !runtimePolicy.readOnly else {
            errorMessage = "This build runs in read-only mode."
            return
        }

        let homeDirectory = harnessSessionService.homeDirectory
        let label = harnessSessionService.label
        do {
            try await Task.detached(priority: .utility) {
                let service = HarnessSessionService(homeDirectory: homeDirectory, label: label)
                try service.uninstall()
            }.value
            refreshHarnessSessionStatus()
        } catch {
            runtimeLogger.error("Failed to stop session watcher", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func openHarnessSessionLogs() {
        harnessSessionService.openLogs()
    }

    func setHarnessProcessName(_ name: String, enabled: Bool) {
        if enabled {
            enabledHarnessProcessNames.insert(name)
        } else {
            enabledHarnessProcessNames.remove(name)
        }
        if enabledHarnessProcessNames.isEmpty {
            enabledHarnessProcessNames = Set(harnessSessionService.defaultProcessNames)
        }
        persist(Array(enabledHarnessProcessNames).sorted(), forKey: enabledHarnessProcessNamesKey)
        refreshHarnessSessionStatus()
        reinstallHarnessSessionWatcherIfNeeded()
    }

    func setHarnessPollIntervalSeconds(_ seconds: Int) {
        harnessPollIntervalSeconds = seconds
        persist(seconds, forKey: harnessPollIntervalSecondsKey)
        reinstallHarnessSessionWatcherIfNeeded()
    }

    func setHarnessMode(_ mode: HarnessSessionMode) {
        harnessMode = mode
        persist(mode.rawValue, forKey: harnessModeKey)
        reinstallHarnessSessionWatcherIfNeeded()
    }

    func setHarnessCustomDurationSeconds(_ seconds: Int) {
        harnessCustomDurationSeconds = max(60, min(seconds, 30 * 24 * 60 * 60))
        persist(harnessCustomDurationSeconds, forKey: harnessCustomDurationSecondsKey)
        if harnessMode == .custom {
            reinstallHarnessSessionWatcherIfNeeded()
        }
    }

    func setHarnessKeepDisplayAwake(_ enabled: Bool) {
        harnessKeepDisplayAwake = enabled
        persist(enabled, forKey: harnessKeepDisplayAwakeKey)
        reinstallHarnessSessionWatcherIfNeeded()
    }

    func setHarnessPowerAdapterOnly(_ enabled: Bool) {
        harnessPowerAdapterOnly = enabled
        persist(enabled, forKey: harnessPowerAdapterOnlyKey)
        reinstallHarnessSessionWatcherIfNeeded()
    }

    func reinstallHarnessSessionWatcherIfNeeded() {
        let status = harnessSessionStatus
        guard status.isInstalled && status.isRunning else { return }
        // Cancel any pending reinstall — coalesces rapid stepper taps / toggle
        // bursts into a single launchctl round-trip.
        harnessReinstallDebounceTask?.cancel()
        harnessReinstallDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await installHarnessSessionWatcher()
        }
    }

    var importedSessionCount: Int {
        Set(importedPrompts.map(Self.sessionKey(for:))).count
    }
}
