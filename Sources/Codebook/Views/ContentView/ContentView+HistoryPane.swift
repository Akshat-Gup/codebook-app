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
    var automationsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Automations")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            if model.automationProjects.isEmpty {
                ContentUnavailableView("No repositories available", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.automationProjects) { project in
                                automationProjectRow(project)
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: 290)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let project = selectedAutomationProject {
                                automationWorkspace(for: project)
                            }
                        }
                        .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            synchronizeAutomationSelection()
        }
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

        return Button {
            withAnimation(CodebookMotion.standard) {
                automationProjectID = project.id
                refreshAutomationProjectStatus()
            }
        } label: {
            HStack(spacing: 10) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(project.promptCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
