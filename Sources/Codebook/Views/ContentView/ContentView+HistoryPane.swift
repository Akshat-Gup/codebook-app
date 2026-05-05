import SwiftUI

extension ContentView {

    // MARK: - History Pane (Section Cards)

    @ViewBuilder
    var hiddenProjectsPane: some View {
        VStack(spacing: 0) {
            historyFilterBar

            if !model.hasVisibleHiddenLibraryItems {
                ContentUnavailableView(
                    model.hasActiveHistoryFilters ? "No hidden items match the current filters" : "Nothing hidden",
                    systemImage: "eye.slash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !model.hiddenProjects.isEmpty {
                            hiddenLibrarySectionCard(
                                title: "Projects",
                                count: model.hiddenProjects.count
                            ) {
                                VStack(spacing: 0) {
                                    ForEach(Array(model.hiddenProjects.enumerated()), id: \.element.id) { index, project in
                                        if index > 0 {
                                            Divider().padding(.leading, 14)
                                        }
                                        hiddenProjectListRow(project)
                                    }
                                }
                            }
                        }

                        if !model.hiddenPromptGroups.isEmpty {
                            hiddenLibrarySectionCard(
                                title: hiddenPromptSectionTitle,
                                count: model.hiddenVisiblePrompts.count
                            ) {
                                VStack(spacing: 0) {
                                    ForEach(Array(model.hiddenPromptGroups.enumerated()), id: \.element.id) { index, group in
                                        if index > 0 {
                                            Divider().padding(.leading, 14)
                                        }
                                        hiddenPromptGroupRow(group)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    @ViewBuilder
    func hiddenLibrarySectionCard(
        title: String,
        count: Int,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            content()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    func hiddenProjectListRow(_ project: ProjectSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let path = project.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Text(project.promptCount == 1 ? "1 prompt" : "\(project.promptCount) prompts")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            unhideProjectIconButton(project: project, size: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var hiddenPromptSectionTitle: String {
        switch model.historyGroupingMode {
        case .commit:
            return "Commits & prompts"
        case .thread:
            return "Threads & prompts"
        }
    }

    @ViewBuilder
    func hiddenPromptGroupRow(_ group: PromptGroup) -> some View {
        if group.structured {
            let groupExpanded = model.isGroupExpanded(group.id)
            let isCommitGroup = group.kind == .commit

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        withAnimation(CodebookMotion.snappy) {
                            model.setGroupExpanded(group.id, expanded: !groupExpanded)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12, height: 14)
                                .rotationEffect(.degrees(groupExpanded ? 90 : 0))
                                .animation(CodebookMotion.snappy, value: groupExpanded)
                            Image(systemName: isCommitGroup ? "arrow.triangle.branch" : "text.bubble")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                            Text(group.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let sub = group.subtitle {
                                Text(sub)
                                    .font(isCommitGroup ? .caption2.monospaced() : .caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(timeString(group.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(group.prompts.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    unhidePromptGroupIconButton(
                        prompts: group.prompts,
                        size: 20,
                        label: isCommitGroup ? "Unhide commit" : "Unhide thread"
                    )
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

                if groupExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(group.prompts.enumerated()), id: \.element.id) { promptIndex, prompt in
                            if promptIndex > 0 {
                                Divider().padding(.leading, 14)
                            }
                            hiddenPromptListRow(prompt)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
                }
            }
        } else if let prompt = group.prompts.first {
            hiddenPromptListRow(prompt)
        }
    }

    func hiddenPromptListRow(_ prompt: ImportedPrompt) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                withAnimation(CodebookMotion.standard) {
                    model.selectPrompt(prompt)
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        PlatformIconView(provider: prompt.provider, size: 22)
                        if let vendor = ModelVendor.detect(modelID: prompt.modelID) {
                            ModelVendorIconView(vendor: vendor, size: 11)
                                .padding(2)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                                )
                                .offset(x: 5, y: 5)
                        }
                    }
                    .frame(width: 28, height: 26, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(prompt.projectName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(prompt.provider.title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(timeString(prompt.capturedAt))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            unhidePromptIconButton(prompt: prompt, size: 20)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedPromptID == prompt.id ? nativeSelectedRowBackground : Color.clear)
        .contentShape(Rectangle())
    }

    func unhideProjectIconButton(project: ProjectSummary, size: CGFloat) -> some View {
        Button {
            model.showProject(project.id)
            model.selectProject(project)
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help("Unhide project")
    }

    func unhidePromptIconButton(prompt: ImportedPrompt, size: CGFloat) -> some View {
        Button {
            withAnimation(CodebookMotion.snappy) {
                model.showPrompt(prompt)
            }
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help("Unhide prompt")
    }

    func unhidePromptGroupIconButton(prompts: [ImportedPrompt], size: CGFloat, label: String) -> some View {
        Button {
            withAnimation(CodebookMotion.snappy) {
                model.showPrompts(prompts)
            }
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    var sessionsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionWatcherControl

                if model.sessionDayGroupsCache.isEmpty {
                    ContentUnavailableView("No sessions", systemImage: "terminal")
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.sessionDayGroupsCache) { group in
                            sessionDayDropdown(group)
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.refreshHarnessSessionStatus()
            expandFirstSessionDayIfNeeded()
        }
        // Refresh harness watcher status while the pane is visible so the live
        // indicator (active app, keep-awake state) reflects reality without a
        // tab switch. 5s is well below the watcher's own poll interval.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            model.refreshHarnessSessionStatus()
        }
    }

    var sessionWatcherControl: some View {
        let status = model.harnessSessionStatus
        let enabled = status.isInstalled && status.isRunning

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CodebookMotion.snappy) {
                    showSessionWatcherOptions.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 14)
                        .rotationEffect(.degrees(showSessionWatcherOptions ? 90 : 0))

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(enabled ? Color.accentColor : .secondary)
                        .frame(width: 20, height: 20)

                    Text("Caffeinate")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: enabled ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(enabled ? Color.accentColor : .secondary)
                        .frame(width: 30, height: 30)
                        .background(AppControlChrome.glassShareButtonBackground(cornerRadius: 8))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep Mac Awake")
                            .font(.system(size: 14, weight: .semibold))
                        Text(sessionWatcherDetailText(status))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task {
                            if enabled {
                                await model.uninstallHarnessSessionWatcher()
                            } else {
                                await model.installHarnessSessionWatcher()
                            }
                        }
                    } label: {
                        Text(enabled ? "Turn Off" : "Turn On")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(enabled ? AppControlChrome.charcoal : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(enabled ? AppControlChrome.softSurface : AppControlChrome.segmentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReadOnlyMode)
                }

                if showSessionWatcherOptions {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("When")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: sessionPickerColumns(count: HarnessSessionMode.allCases.count), spacing: 10) {
                                ForEach(HarnessSessionMode.allCases, id: \.self) { mode in
                                    sessionModeButton(mode)
                                }
                            }
                            if model.harnessMode == .custom {
                                sessionCustomDurationControl
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        if model.harnessMode == .agentSessions {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Apps")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: sessionPickerColumns(count: model.harnessSessionService.defaultProcessNames.count), spacing: 10) {
                                    ForEach(model.harnessSessionService.defaultProcessNames, id: \.self) { name in
                                        sessionProcessToggle(name)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Options")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: sessionPickerColumns(count: 2), spacing: 10) {
                                sessionOptionToggle(
                                    title: "Keep display awake",
                                    systemImage: "display",
                                    isOn: model.harnessKeepDisplayAwake
                                ) {
                                    model.setHarnessKeepDisplayAwake(!model.harnessKeepDisplayAwake)
                                }
                                sessionOptionToggle(
                                    title: "Only when plugged in",
                                    systemImage: "powerplug",
                                    isOn: model.harnessPowerAdapterOnly
                                ) {
                                    model.setHarnessPowerAdapterOnly(!model.harnessPowerAdapterOnly)
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(sessionPanelBackground)
        .animation(CodebookMotion.snappy, value: showSessionWatcherOptions)
    }

    var sessionPanelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
    }

    func sessionPickerColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 96), spacing: 10, alignment: .leading), count: max(count, 1))
    }

    static func compactDurationLabel(milliseconds: Int) -> String {
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        let seconds = Double(milliseconds) / 1_000
        return String(format: "%.1fs", seconds)
    }

    static func compactDurationLabel(seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    func sessionWatcherDetailText(_ status: HarnessSessionStatus) -> String {
        if model.harnessMode == .agentSessions {
            if let active = status.activeProcessName {
                let name = IntegrationProvider(rawValue: active)?.title ?? active
                return "While \(name) is running"
            }
            return "While selected agent apps are running"
        }
        if model.harnessMode == .custom {
            return "For \(Self.compactDurationLabel(seconds: TimeInterval(model.harnessCustomDurationSeconds)))"
        }
        return "\(model.harnessMode.title)"
    }

    func sessionModeButton(_ mode: HarnessSessionMode) -> some View {
        let selected = model.harnessMode == mode
        return Button {
            model.setHarnessMode(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(mode.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? AppControlChrome.segmentBlue : AppControlChrome.softSurface.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var sessionCustomDurationControl: some View {
        let days = model.harnessCustomDurationSeconds / (24 * 60 * 60)
        let hours = (model.harnessCustomDurationSeconds % (24 * 60 * 60)) / (60 * 60)
        let minutes = (model.harnessCustomDurationSeconds % (60 * 60)) / 60

        return HStack(spacing: 10) {
            sessionDurationStepper(
                title: "Days",
                value: days,
                range: 0...30
            ) { newDays in
                setCustomDuration(days: newDays, hours: hours, minutes: minutes)
            }
            sessionDurationStepper(
                title: "Hours",
                value: hours,
                range: 0...23
            ) { newHours in
                setCustomDuration(days: days, hours: newHours, minutes: minutes)
            }
            sessionDurationStepper(
                title: "Minutes",
                value: minutes,
                range: 0...59
            ) { newMinutes in
                setCustomDuration(days: days, hours: hours, minutes: newMinutes)
            }
        }
        .padding(10)
        .background(AppControlChrome.glassShareButtonBackground(cornerRadius: 10))
    }

    func sessionDurationStepper(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Stepper(value: Binding(
            get: { value },
            set: { onChange($0) }
        ), in: range) {
            HStack(spacing: 8) {
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .leading)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    func setCustomDuration(days: Int, hours: Int, minutes: Int) {
        let seconds = days * 24 * 60 * 60 + hours * 60 * 60 + minutes * 60
        model.setHarnessCustomDurationSeconds(max(seconds, 60))
    }

    func sessionProcessToggle(_ name: String) -> some View {
        let isOn = model.enabledHarnessProcessNames.contains(name)
        return Button {
            model.setHarnessProcessName(name, enabled: !isOn)
        } label: {
            HStack(spacing: 8) {
                if let provider = IntegrationProvider(rawValue: name) {
                    PlatformIconView(provider: provider, size: 16)
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                Text(IntegrationProvider(rawValue: name)?.title ?? name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppControlChrome.softSurface.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func sessionOptionToggle(title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppControlChrome.softSurface.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func sessionDayDropdown(_ group: SessionDayGroup) -> some View {
        let isExpanded = expandedSessionDayIDs.contains(group.id)
        let totalDuration = group.sessions.reduce(0) { $0 + $1.duration }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CodebookMotion.snappy) {
                    toggleSessionDay(group.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 14)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(group.sessions.count) sessions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.compactDurationLabel(seconds: totalDuration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.sessions) { session in
                        sessionRow(session)
                        if session.id != group.sessions.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func sessionRow(_ session: SessionSummary) -> some View {
        let latest = session.prompts.last
        return Button {
            if let latest, session.canResume {
                model.openThread(for: latest)
            } else if let latest {
                withAnimation(CodebookMotion.standard) {
                    model.selectProject(ProjectSummary(
                        id: session.projectID,
                        name: session.projectName,
                        path: latest.projectPath,
                        promptCount: session.prompts.count,
                        isManual: false
                    ))
                    model.selectPrompt(latest)
                }
            }
        } label: {
            HStack(spacing: 10) {
                PlatformIconView(provider: session.provider, size: 22)
                    .frame(width: 28, height: 26, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.provider.title)
                        Text("·")
                        Text(session.prompts.count == 1 ? "1 prompt" : "\(session.prompts.count) prompts")
                        if session.commitCount > 0 {
                            Text("·")
                            Text(session.commitCount == 1 ? "1 commit" : "\(session.commitCount) commits")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.lastActiveAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text(Self.compactDurationLabel(seconds: session.duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Image(systemName: session.canResume ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    func toggleSessionDay(_ id: String) {
        if expandedSessionDayIDs.contains(id) {
            expandedSessionDayIDs.remove(id)
        } else {
            expandedSessionDayIDs.insert(id)
        }
    }

    func expandFirstSessionDayIfNeeded() {
        guard expandedSessionDayIDs.isEmpty,
              let first = model.sessionDayGroupsCache.first
        else { return }
        expandedSessionDayIDs.insert(first.id)
    }

    @ViewBuilder
    var historyPane: some View {
        let isSearchMode = !model.searchInputText.isEmpty
        let isSearchPending = isSearchMode && model.searchInputText != model.searchText
        let shouldShowAISearchResults = model.searchMode == .ai &&
            model.aiSearchQuery == model.searchInputText &&
            !model.searchInputText.isEmpty

        VStack(spacing: 0) {
            historyFilterBar

            if shouldShowProjectToolbar && !model.isDashboardSelected {
                projectToolbar
            }

            if shouldShowAISearchResults {
                aiSearchResultsPane
            } else if isSearchMode {
                searchTabBar
                Divider().opacity(0.5)

                if isSearchPending {
                    searchResultsLoading
                } else if model.visiblePrompts.isEmpty {
                    ContentUnavailableView(model.hasActiveHistoryFilters ? "No results match the current filters" : "No results", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Group {
                        switch model.searchTab {
                        case .all:
                            searchResultsAll
                        case .commits:
                            searchResultsByCommits
                        case .dates:
                            searchResultsByDates
                        case .projects:
                            searchResultsByProjects
                        case .tags:
                            searchResultsByTags
                        case .providers:
                            searchResultsByProviders
                        }
                    }
                    .id(model.searchTab)
                    .contentTransition(.opacity)
                    .animation(CodebookMotion.standard, value: model.searchTab)
                }
            } else if model.visiblePrompts.isEmpty, model.isRefreshing {
                VStack {
                    Spacer()
                    loadingStateView()
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visiblePrompts.isEmpty {
                ContentUnavailableView(model.hasActiveHistoryFilters ? "No prompts match the current filters" : "No prompts", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(model.dayGroups.enumerated()), id: \.element.id) { index, day in
                            daySectionCard(day, isFirst: index == 0)
                        }
                    }
                    .padding(14)
                }
                .id(model.selectedProjectID ?? "")
                .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .top)))
            }
        }
    }

    func daySectionCard(_ day: DayPromptGroup, isFirst: Bool) -> some View {
        let expanded = dayIsExpanded(day, isFirst: isFirst)
        let prompts = day.groups.flatMap(\.prompts)
        let promptCount = prompts.count
        let dayKeyStr = String(day.id.dropFirst("day-".count))

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    toggleDayExpansion(day, isFirst: isFirst)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, height: 14)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .animation(CodebookMotion.snappy, value: expanded)
                        Text(day.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(costLabel(for: prompts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(responseTimeLabel(for: prompts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(promptCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                dayActionButtons(prompts: prompts, dayKey: dayKeyStr, iconSize: 20)
            }
            .padding(.horizontal, 4)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(day.groups.enumerated()), id: \.element.id) { groupIndex, group in
                        if groupIndex > 0 {
                            Divider().padding(.horizontal, 12)
                        }

                        if group.structured {
                            VStack(alignment: .leading, spacing: 0) {
                                let groupExpanded = model.isGroupExpanded(group.id)
                                let isCommitGroup = group.kind == .commit
                                let isOrphaned = isCommitGroup && group.prompts.contains { $0.commitOrphaned }
                                let groupAccent = isOrphaned ? Color.orange : Color.secondary
                                let groupIcon = isCommitGroup ? "arrow.triangle.branch" : "text.bubble"
                                let leadPrompt = group.prompts.first

                                HStack(alignment: .center, spacing: 6) {
                                    Button {
                                        withAnimation(CodebookMotion.snappy) {
                                            model.setGroupExpanded(group.id, expanded: !groupExpanded)
                                        }
                                    } label: {
                                        HStack(alignment: .center, spacing: 6) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 12, height: 14)
                                                .rotationEffect(.degrees(groupExpanded ? 90 : 0))
                                                .animation(CodebookMotion.snappy, value: groupExpanded)
                                            Image(systemName: groupIcon)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(groupAccent)
                                                .frame(width: 14, height: 14)
                                            if isOrphaned {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundStyle(.orange)
                                                    .frame(width: 14, height: 14)
                                            }
                                            Text(group.title)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(1)
                                            if let sub = group.subtitle {
                                                Text(sub)
                                                    .font(isCommitGroup ? .caption2.monospaced() : .caption2)
                                                    .foregroundStyle(.tertiary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            if isOrphaned {
                                                Text("Orphaned")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.red)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.red.opacity(0.1))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Spacer(minLength: 8)
                                    groupActionButtons(group: group, leadPrompt: leadPrompt)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                if groupExpanded {
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.prompts.enumerated()), id: \.element.id) { promptIndex, prompt in
                                            if promptIndex > 0 {
                                                Divider().padding(.leading, 14)
                                            }
                                            promptRowButton(prompt, diffContextPrompts: group.prompts)
                                        }
                                    }
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                                    ))
                                }
                            }
                        } else {
                            promptRowButton(group.prompts[0], diffContextPrompts: group.prompts)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                ))
            }
        }
        .animation(CodebookMotion.snappy, value: expanded)
    }

    func automationProjectRow(_ project: ProjectSummary) -> some View {
        let isSelected = selectedAutomationProject?.id == project.id
        let status = model.repoAutomationStatus(for: project)
        let prompts = prompts(for: project)
        let latest = prompts.map(\.effectiveDate).max()
        let providers = Array(Set(prompts.map(\.provider))).sorted { $0.rawValue < $1.rawValue }.prefix(4)

        return Button {
            withAnimation(CodebookMotion.standard) {
                automationProjectID = project.id
                refreshAutomationProjectStatus()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: status?.hookInstalled == true ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status?.hookInstalled == true ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(project.promptCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    ForEach(Array(providers), id: \.self) { provider in
                        PlatformIconView(provider: provider, size: 14)
                    }

                    Spacer(minLength: 0)

                    if let latest {
                        Text(latest.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sidebarRowChrome(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.gentle, value: isSelected)
    }

    func automationWorkspace(for project: ProjectSummary) -> some View {
        let status = automationProjectStatus
        let promptsReady = status?.promptStoreExists == true
        let turnedOn = promptsReady && status?.hookInstalled == true
        let projectPrompts = prompts(for: project)
        let sessions = Set(projectPrompts.compactMap { $0.sourceContextID ?? $0.sourcePath }).count
        let commits = Set(projectPrompts.compactMap(\.commitSHA)).count

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                if let path = project.path {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                automationStatusPill(
                    label: turnedOn ? "Turned On" : "Turned Off",
                    systemImage: turnedOn ? "checkmark.circle" : "circle"
                )
                automationStatusPill(
                    label: promptsReady ? "prompts/" : "No prompts/",
                    systemImage: promptsReady ? "folder" : "folder.badge.plus"
                )
                if let promptCount = status?.promptCount {
                    automationStatusPill(
                        label: "\(promptCount) Prompts",
                        systemImage: "text.bubble"
                    )
                }
                automationStatusPill(
                    label: "\(sessions) Sessions",
                    systemImage: "terminal"
                )
                automationStatusPill(
                    label: "\(commits) Commits",
                    systemImage: "arrow.triangle.branch"
                )
            }

            automationTrackedProvidersSection(project: project)

            HStack(spacing: 10) {
                Button(turnedOn ? "Open prompts/" : "Turn On") {
                    if turnedOn {
                        model.openPromptStore(for: project)
                    } else {
                        promptStoreConfirmation = PromptStoreConfirmationRequest(project: project, action: .turnOn)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppControlChrome.segmentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Sync Now") {
                    Task {
                        automationProjectID = project.id
                        await model.exportPrompts(for: project)
                        refreshAutomationProjectStatus()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppControlChrome.charcoal)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppControlChrome.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(model.isReadOnlyMode)

                if turnedOn {
                    Button("Turn Off") {
                        Task {
                            await model.uninstallRepoAutomation(for: project)
                            refreshAutomationProjectStatus()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppControlChrome.charcoal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppControlChrome.softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(model.isReadOnlyMode)
                }
            }

            HStack(spacing: 10) {
                Button(promptsReady ? "Open Folder" : "Create prompts/") {
                    if promptsReady {
                        model.openPromptStore(for: project)
                    } else {
                        promptStoreConfirmation = PromptStoreConfirmationRequest(project: project, action: .createFolder)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppControlChrome.charcoal)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppControlChrome.softSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if promptsReady {
                    Menu {
                        ForEach(RepoAutomationExportMode.allCases, id: \.self) { mode in
                            Button {
                                automationExportMode = mode
                                Task {
                                    await model.reorganizePromptStore(for: project, mode: mode)
                                    refreshAutomationProjectStatus()
                                }
                            } label: {
                                Label(mode.title, systemImage: mode == (model.repoAutomationSettings(for: project)?.exportMode ?? .commit) ? "checkmark" : mode.systemImage)
                            }
                        }
                    } label: {
                        Text("Reorganize")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppControlChrome.charcoal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppControlChrome.softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Delete prompts/") {
                        promptStoreConfirmation = PromptStoreConfirmationRequest(project: project, action: .deleteFolder)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.18), lineWidth: 0.5)
                    )
                }

                if model.isCLIEnabled {
                    Button("Copy CLI Path") {
                        copyText(cliPathLabel)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppControlChrome.charcoal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppControlChrome.softSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    func automationTrackedProvidersSection(project: ProjectSummary) -> some View {
        let settings = model.repoAutomationSettings(for: project) ?? RepoAutomationSettings()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Sources to export")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(IntegrationProvider.allCases.enumerated()), id: \.offset) { index, provider in
                    if index > 0 {
                        Divider().padding(.leading, 38)
                    }
                    let isOn = settings.trackedProviders.contains(provider)
                    ProviderSourceToggleRow(
                        provider: provider,
                        isOn: isOn,
                        isEnabled: !model.isReadOnlyMode
                    ) {
                        model.setRepoAutomationTrackedProvider(provider, enabled: !isOn, for: project)
                        refreshAutomationProjectStatus()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppControlChrome.softSurface.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 1)
            )
        }
    }

    func prompts(for project: ProjectSummary) -> [ImportedPrompt] {
        model.importedPrompts.filter { $0.projectKey == project.id }
    }

    func automationStatusPill(label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(AppControlChrome.charcoal.opacity(0.88))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppControlChrome.softSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 0.5)
        )
    }

    func performPromptStoreConfirmation(_ request: PromptStoreConfirmationRequest) async {
        defer {
            promptStoreConfirmation = nil
            refreshAutomationProjectStatus()
        }

        switch request.action {
        case .createFolder:
            do {
                model.setRepoAutomationExportMode(automationExportMode, for: request.project)
                _ = try model.createPromptStore(for: request.project)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        case .turnOn:
            do {
                model.setRepoAutomationExportMode(automationExportMode, for: request.project)
                _ = try model.createPromptStore(for: request.project)
            } catch {
                model.errorMessage = error.localizedDescription
                return
            }
            await model.installRepoAutomationHooks(for: request.project)
            await model.exportPrompts(for: request.project)
        case .deleteFolder:
            await model.resetPromptStore(for: request.project)
        }
    }

    var selectedAutomationProject: ProjectSummary? {
        let projects = model.automationProjects
        guard let automationProjectID else { return projects.first }
        return projects.first(where: { $0.id == automationProjectID }) ?? projects.first
    }

    func synchronizeAutomationSelection() {
        let projects = model.automationProjects
        if let automationProjectID,
           projects.contains(where: { $0.id == automationProjectID }) {
            refreshAutomationProjectStatus()
            return
        }

        automationProjectID = projects.first?.id
        refreshAutomationProjectStatus()
    }

    func refreshAutomationProjectStatus() {
        guard let project = selectedAutomationProject else {
            automationProjectStatus = nil
            return
        }
        automationProjectStatus = model.repoAutomationStatus(for: project)
        automationExportMode = model.repoAutomationSettings(for: project)?.exportMode ?? .date
    }

    var cliPathLabel: String {
        let helperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/codebook-cli", isDirectory: false)
            .path

        if FileManager.default.isExecutableFile(atPath: helperPath) {
            return helperPath
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/CodebookCLI", isDirectory: false)
            .path
    }

    func copyText(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func dayIsExpanded(_ day: DayPromptGroup, isFirst: Bool) -> Bool {
        if isFirst && !collapsedFirstDay { return true }
        return model.isDayExpanded(day.id)
    }

    func toggleDayExpansion(_ day: DayPromptGroup, isFirst: Bool) {
        let currentlyExpanded = dayIsExpanded(day, isFirst: isFirst)
        withAnimation(CodebookMotion.snappy) {
            if currentlyExpanded {
                // Collapsing
                if isFirst && !collapsedFirstDay {
                    collapsedFirstDay = true
                } else {
                    model.setDayExpanded(day.id, expanded: false)
                }
            } else {
                // Expanding
                model.setDayExpanded(day.id, expanded: true)
            }
        }
    }

    func promptRowButton(
        _ prompt: ImportedPrompt,
        diffContextPrompts: [ImportedPrompt]? = nil,
        showsCommitDiff: Bool? = nil
    ) -> some View {
        let isSearching = !model.searchText.isEmpty
        let shouldShowCommitDiff = showsCommitDiff ?? promptRowShowsCommitDiff(prompt, within: diffContextPrompts)
        return HStack(alignment: .center, spacing: 6) {
            Button(action: {
                withAnimation(CodebookMotion.standard) {
                    model.selectPrompt(prompt)
                }
            }) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        PlatformIconView(provider: prompt.provider, size: 22)
                        if let vendor = ModelVendor.detect(modelID: prompt.modelID) {
                            ModelVendorIconView(vendor: vendor, size: 11)
                                .padding(2)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                                )
                                .offset(x: 5, y: 5)
                        }
                    }
                    .frame(width: 28, height: 26, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        if isSearching {
                            highlightedText(prompt.title, searchTerms: model.searchText)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        } else {
                            Text(prompt.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(prompt.projectName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if shouldShowCommitDiff {
                                promptRowCommitDiffFragment(prompt)
                            }
                            Text(prompt.provider.title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            if !prompt.displayTags.isEmpty {
                                Text(prompt.displayTags.prefix(2).joined(separator: " \u{00B7} "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Text(timeString(prompt.capturedAt))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                copyPromptIconButton(prompt: prompt, size: 20)
                savePromptButton(prompt: prompt, size: 20)
                hidePromptButton(prompt: prompt, size: 20)
            }
            .padding(.trailing, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedPromptID == prompt.id ? nativeSelectedRowBackground : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func promptRowCommitDiffFragment(_ prompt: ImportedPrompt) -> some View {
        let ins = prompt.commitInsertions ?? 0
        let del = prompt.commitDeletions ?? 0
        if ins > 0 || del > 0 {
            HStack(spacing: 4) {
                Text("+\(ins)")
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("−\(del)")
                    .foregroundStyle(Color.red.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption2.weight(.semibold))
        } else if let files = prompt.commitFilesChanged, files > 0 {
            Text("\(files) files")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    func promptRowShowsCommitDiff(_ prompt: ImportedPrompt, within prompts: [ImportedPrompt]?) -> Bool {
        guard prompt.hasCommitLineStats else { return false }
        let contextPrompts = prompts ?? model.visiblePrompts
        return PromptThreading.latestCommitDiffPromptIDs(in: contextPrompts).contains(prompt.id)
    }

    @ViewBuilder
    func searchGroupCommitDiffTrailing(_ prompt: ImportedPrompt) -> some View {
        let ins = prompt.commitInsertions ?? 0
        let del = prompt.commitDeletions ?? 0
        if ins > 0 || del > 0 {
            HStack(spacing: 3) {
                Text("+\(ins)")
                    .foregroundStyle(Color.green.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("−\(del)")
                    .foregroundStyle(Color.red.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption2.weight(.semibold))
        }
    }

    func savePromptButton(prompt: ImportedPrompt, size: CGFloat) -> some View {
        let isSaved = model.isPromptSaved(prompt.id)

        return Button {
            withAnimation(CodebookMotion.snappy) {
                model.toggleSavedPrompt(prompt)
            }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSaved ? savedOnForeground : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSaved ? savedOnBackground : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isSaved)
        .help(isSaved ? "Remove from Saved" : "Save prompt")
    }

    func hidePromptButton(prompt: ImportedPrompt, size: CGFloat) -> some View {
        return Button {
            withAnimation(CodebookMotion.snappy) {
                model.hidePrompt(prompt)
            }
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .help("Hide prompt")
    }

    func copyPromptIconButton(prompt: ImportedPrompt, size: CGFloat) -> some View {
        let isCopied = copiedPromptID == prompt.id

        return Button {
            copyPrompt(prompt)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCopied ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isCopied ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isCopied)
        .help(isCopied ? "Copied" : "Copy prompt")
    }

    func saveCommitButton(sha: String, size: CGFloat) -> some View {
        let isSaved = model.isCommitSaved(sha)

        return Button {
            withAnimation(CodebookMotion.snappy) {
                model.toggleSavedCommit(sha)
            }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSaved ? savedOnForeground : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSaved ? savedOnBackground : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isSaved)
        .help(isSaved ? "Remove commit from Saved" : "Save commit")
    }

    func saveDayButton(prompts: [ImportedPrompt], size: CGFloat) -> some View {
        savePromptCollectionButton(
            prompts: prompts,
            size: size,
            saveHelp: "Save day",
            removeHelp: "Remove day from Saved"
        )
    }

    func saveThreadButton(prompts: [ImportedPrompt], size: CGFloat) -> some View {
        savePromptCollectionButton(
            prompts: prompts,
            size: size,
            saveHelp: "Save thread",
            removeHelp: "Remove thread from Saved"
        )
    }

    func savePromptCollectionButton(
        prompts: [ImportedPrompt],
        size: CGFloat,
        saveHelp: String,
        removeHelp: String
    ) -> some View {
        let isSaved = model.isDaySaved(prompts)

        return Button {
            withAnimation(CodebookMotion.snappy) {
                model.toggleSavedDay(prompts)
            }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSaved ? savedOnForeground : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSaved ? savedOnBackground : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isSaved)
        .help(isSaved ? removeHelp : saveHelp)
    }

    func dayActionButtons(prompts: [ImportedPrompt], dayKey: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            saveDayButton(prompts: prompts, size: iconSize)
            batchSendMenu(label: "Copy day prompts", scope: .day(key: dayKey))
        }
    }

    @ViewBuilder
    func groupActionButtons(group: PromptGroup, leadPrompt: ImportedPrompt?) -> some View {
        if group.kind == .commit, let sha = leadPrompt?.commitSHA {
            commitActionButtons(sha: sha, prompts: group.prompts)
        } else {
            threadActionButtons(groupID: group.id, prompts: group.prompts)
        }
    }

    func commitActionButtons(sha: String, prompts: [ImportedPrompt]) -> some View {
        HStack(spacing: 6) {
            saveCommitButton(sha: sha, size: 20)
            batchSendMenu(label: "Copy commit prompts", scope: .commit(sha: sha))
            hidePromptGroupIconButton(prompts: prompts, size: 20, label: "Hide commit")
        }
    }

    func threadActionButtons(groupID: String, prompts: [ImportedPrompt]) -> some View {
        HStack(spacing: 6) {
            saveThreadButton(prompts: prompts, size: 20)
            batchSendMenu(label: "Copy thread prompts", scope: .thread(key: groupID), prompts: prompts)
            hidePromptGroupIconButton(prompts: prompts, size: 20, label: "Hide thread")
        }
    }

    func hidePromptGroupIconButton(prompts: [ImportedPrompt], size: CGFloat, label: String) -> some View {
        Button {
            withAnimation(CodebookMotion.snappy) {
                model.hidePrompts(prompts)
            }
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    func savePromptPillButton(prompt: ImportedPrompt) -> some View {
        let isSaved = model.isPromptSaved(prompt.id)

        return Button {
            withAnimation(CodebookMotion.snappy) {
                model.toggleSavedPrompt(prompt)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 10))
                    .contentTransition(.symbolEffect(.replace))
                Text(isSaved ? "Saved" : "Save")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.interpolate)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSaved ? savedOnBackground : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSaved ? savedOnForeground : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSaved ? Color.white.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.3),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isSaved)
    }

    func hidePromptPillButton(prompt: ImportedPrompt) -> some View {
        let isHidden = model.isPromptHidden(prompt)

        return Button {
            withAnimation(CodebookMotion.snappy) {
                if isHidden {
                    model.showPrompt(prompt)
                } else {
                    model.hidePrompt(prompt)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isHidden ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .contentTransition(.symbolEffect(.replace))
                Text(isHidden ? "Unhide" : "Hide")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.interpolate)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(CodebookMotion.snappy, value: isHidden)
        .help(isHidden ? "Unhide prompt" : "Hide prompt")
    }

    /// Batch clipboard copy is scoped to a single indexed repository (not All Projects or other sidebar modes).
    var selectedProjectSupportsBatchClipboardCopy: Bool {
        guard let summary = model.selectedProjectSummary else { return false }
        return summary.id != "all-projects" && summary.path != nil
    }

    /// Project-only toolbar actions should stay hidden for the synthetic All Projects row.
    var shouldShowProjectToolbar: Bool {
        guard let summary = model.selectedProjectSummary else { return false }
        return summary.id != "all-projects"
    }

    var historyGroupingModeBinding: Binding<HistoryGroupingMode> {
        Binding(
            get: { model.historyGroupingMode },
            set: { model.setHistoryGroupingMode($0) }
        )
    }

    var historyFilterBar: some View {
        return HStack(spacing: 8) {
            Button {
                showingHistoryDateRangePopover.toggle()
            } label: {
                filterControlLabel(
                    title: historyDateRangeLabel,
                    isActive: model.historyFilterStartDate != nil || model.historyFilterEndDate != nil
                ) {
                    let hasRange = model.historyFilterStartDate != nil || model.historyFilterEndDate != nil
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hasRange ? Color.accentColor : AppControlChrome.charcoal)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingHistoryDateRangePopover, arrowEdge: .top) {
                historyDateRangePopover
            }

            SidebarStyleSegmentedControl(
                selection: historyGroupingModeBinding,
                options: Array(HistoryGroupingMode.allCases),
                minSegmentWidth: 72
            ) { option, isSelected in
                HStack(spacing: 6) {
                    Image(systemName: option == .thread ? "text.bubble" : "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            }
            .fixedSize()

            Menu {
                Button {
                    model.setHistoryFilterPlatform(nil)
                } label: {
                    platformMenuItemLabel(title: "All Platforms", provider: nil)
                }

                Divider()

                ForEach([IntegrationProvider.codex, .claude, .copilot, .cursor, .opencode, .antigravity], id: \.self) { provider in
                    Button {
                        model.setHistoryFilterPlatform(provider)
                    } label: {
                        platformMenuItemLabel(title: provider.title, provider: provider)
                    }
                }
            } label: {
                filterControlLabel(
                    title: model.historyFilterPlatform?.title ?? "All Platforms",
                    isActive: model.historyFilterPlatform != nil
                ) {
                    if let provider = model.historyFilterPlatform {
                        PlatformIconView(provider: provider, size: 14)
                    } else {
                        AllPlatformsIconView(size: 13)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Spacer(minLength: 0)

            if selectedProjectSupportsBatchClipboardCopy {
                batchSendToolbarButton(
                    label: "Copy all prompts shown for this repository",
                    scope: .repo
                )
            }

            if model.hasActiveHistoryFilters {
                Button("Clear") {
                    model.clearHistoryFilters()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

struct SessionDayGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let sessions: [SessionSummary]
    let lastActiveAt: Date
}

struct SessionSummary: Identifiable, Hashable {
    let id: String
    let projectID: String
    let projectName: String
    let provider: IntegrationProvider
    let title: String
    let prompts: [ImportedPrompt]
    let startedAt: Date
    let lastActiveAt: Date
    let duration: TimeInterval
    let commitCount: Int
    let canResume: Bool
}
