import SwiftUI

extension ContentView {

    // MARK: - Sidebar

    /// Drives list insert/remove animation when pinned / hidden sections change shape.
    var sidebarListStructureKey: String {
        let pinSig = model.pinnedProjectSummaries.map(\.id).sorted().joined(separator: ",")
        return "\(model.hiddenProjects.count)|\(model.hiddenPrompts.count)|\(pinSig)"
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    AppKitSearchField(
                        text: $model.searchInputText,
                        isFocused: $isSearchFieldFocused,
                        placeholder: model.searchMode == .ai ? "Ask anything..." : "Search prompts...",
                        focusRequestID: model.searchFocusRequestID,
                        onTextChange: {
                            model.handleSearchChange()
                        },
                        onSubmit: {
                            guard model.searchMode == .ai else { return }
                            model.runAISearch()
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(searchFieldBorderColor, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .animation(CodebookMotion.gentle, value: isSearchFieldFocused)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                searchModeToggle
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowSpacing) {
                    sidebarSpecialRow(
                        title: "Dashboard",
                        systemImage: "square.grid.2x2",
                        count: model.importedPrompts.count,
                        isSelected: model.isDashboardSelected
                    ) {
                        withAnimation(CodebookMotion.pane) {
                            model.selectDashboard()
                        }
                    }

                    sidebarSpecialRow(
                        title: "Insights",
                        systemImage: "sparkle.magnifyingglass",
                        count: 0,
                        isSelected: model.isInsightsSelected
                    ) {
                        withAnimation(CodebookMotion.pane) {
                            model.selectInsights()
                        }
                    }

                    sidebarSpecialRow(
                        title: "Saved",
                        systemImage: "bookmark",
                        count: model.savedItemCount,
                        isSelected: model.isSavedSelected
                    ) {
                        withAnimation(CodebookMotion.pane) {
                            model.selectSaved()
                        }
                    }

                    sidebarSpecialRow(
                        title: "Sessions",
                        systemImage: "moon.zzz",
                        count: model.importedSessionCount,
                        isSelected: model.isAutomationsSelected
                    ) {
                        withAnimation(CodebookMotion.pane) {
                            model.selectAutomations()
                        }
                    }

                    sidebarSpecialRow(
                        title: "Plugins",
                        systemImage: "puzzlepiece.extension",
                        count: model.ecosystemCatalog.count,
                        isSelected: model.isEcosystemSelected
                    ) {
                        withAnimation(CodebookMotion.pane) {
                            model.selectEcosystem()
                        }
                    }

                    if !model.hiddenProjects.isEmpty || !model.hiddenPrompts.isEmpty {
                        sidebarSpecialRow(
                            title: "Hidden",
                            systemImage: "eye.slash",
                            count: model.hiddenProjects.count + model.hiddenPrompts.count,
                            isSelected: model.isHiddenProjectsSelected
                        ) {
                            withAnimation(CodebookMotion.pane) {
                                model.selectHiddenProjects()
                            }
                        }
                        .transition(.sidebarSection)
                    }

                    if !model.pinnedProjectSummaries.isEmpty {
                        Group {
                            Text("Pinned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 2)
                            ForEach(model.pinnedProjectSummaries) { project in
                                projectRow(project)
                            }
                            Divider()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .transition(.sidebarSection)
                    }

                    ForEach(model.otherProjectSummaries) { project in
                        projectRow(project)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .animation(CodebookMotion.sidebarList, value: sidebarListStructureKey)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                sidebarToolbarIconButton(
                    systemImage: "arrow.clockwise",
                    help: "Refresh",
                    isDisabled: model.isRefreshing
                ) {
                    Task { await model.refresh(forceScan: true) }
                }

                if model.isRefreshing {
                    loadingStateView(compact: true)
                        .frame(maxWidth: 180, alignment: .leading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                sidebarToolbarIconButton(systemImage: "gearshape", help: "Settings") {
                    model.settingsPresented = true
                }
            }
            .animation(CodebookMotion.snappy, value: model.isRefreshing)
            .padding(12)
        }
    }

    var searchModeToggle: some View {
        SidebarStyleSegmentedControl(
            selection: Binding(
                get: { model.searchMode },
                set: { model.setSearchMode($0) }
            ),
            options: [.keyword, .ai],
            trackPadding: 1,
            segmentMinHeight: 26,
            minSegmentWidth: 30,
            optionHelp: { mode in
                switch mode {
                case .keyword: return "Keyword search"
                case .ai: return "AI search"
                }
            }
        ) { mode, isSelected in
            Image(systemName: mode == .ai ? "brain" : "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
        }
    }

    var searchFieldBorderColor: Color {
        if isSearchFieldFocused {
            return Color.accentColor.opacity(0.65)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }

    var sidebarToolbarChrome: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
    }

    @ViewBuilder
    func sidebarToolbarIconButton(systemImage: String, help: String, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(sidebarToolbarChrome)
        .help(help)
    }

    @ViewBuilder
    func batchSendToolbarButton(label: String, scope: BatchScope) -> some View {
        Button {
            copyBatchPrompts(scope: scope)
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(sidebarToolbarChrome)
        .help(label)
    }

    var nativeSelectedRowBackground: Color {
        Color(nsColor: .quaternaryLabelColor)
            .opacity(controlActiveState == .key ? 0.24 : 0.18)
    }

    var nativeSelectedRowBorder: Color {
        Color(nsColor: .separatorColor)
            .opacity(controlActiveState == .key ? 0.28 : 0.18)
    }

    var nativeHoveredRowBackground: Color {
        Color(nsColor: .quaternaryLabelColor).opacity(0.07)
    }

    /// Dark filled chip when a prompt/commit is saved (pin-style active state).
    var savedOnBackground: Color {
        Color(white: 0.11)
    }

    var savedOnForeground: Color {
        Color.white
    }

    @ViewBuilder
    func sidebarRowChrome(isSelected: Bool, isHovered: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? nativeSelectedRowBackground : (isHovered ? nativeHoveredRowBackground : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? nativeSelectedRowBorder : .clear, lineWidth: 1)
            )
    }

    func sidebarRowCountText(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    func sidebarProjectCountLabel(_ value: Int) -> some View {
        Text(sidebarRowCountText(value))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    func sidebarSpecialRow(title: String, systemImage: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                sidebarProjectCountLabel(count)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sidebarRowChrome(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(CodebookMotion.sidebarChrome, value: "\(title)|\(isSelected)")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func projectRowRepoTrailingActions(
        project: ProjectSummary,
        isSelected: Bool,
        isHovered: Bool,
        isPinned: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(CodebookMotion.sidebarChrome) {
                    model.togglePinnedProject(project.id)
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.caption.weight(.semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isPinned ? .primary : (isSelected || isHovered ? .secondary : .tertiary))

            Menu {
                Button(isPinned ? "Unpin" : "Pin") {
                    withAnimation(CodebookMotion.sidebarChrome) {
                        model.togglePinnedProject(project.id)
                    }
                }
                Button("Hide") {
                    withAnimation(CodebookMotion.sidebarList) {
                        model.hideProject(project.id)
                    }
                }
                if project.isManual, let path = project.path {
                    Divider()
                    Button("Remove Folder", role: .destructive) {
                        withAnimation(CodebookMotion.sidebarList) {
                            model.removeManualFolder(path)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(isSelected || isHovered ? .secondary : .tertiary)
        }
        .frame(width: SidebarMetrics.actionColumn, alignment: .trailing)
    }

    @ViewBuilder
    func projectRow(_ project: ProjectSummary) -> some View {
        let isSelected = model.selectedProjectID == project.id
        let isHovered = hoveredProjectRowID == project.id
        let isPinned = model.isProjectPinned(project.id)

        Button {
            withAnimation(CodebookMotion.pane) {
                model.selectProject(project)
            }
        } label: {
            if project.id == "all-projects" {
                HStack(alignment: .center, spacing: SidebarMetrics.rowSpacing) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack(alignment: .center, spacing: SidebarMetrics.rowSpacing) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    sidebarProjectCountLabel(project.promptCount)
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .padding(.trailing, 10 + SidebarMetrics.actionColumn + SidebarMetrics.countToActionGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if project.id == "all-projects" {
                HStack(spacing: 8) {
                    sidebarProjectCountLabel(project.promptCount)
                    Button(action: { model.addFolder() }) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isSelected || isHovered ? .secondary : .tertiary)
                    .help("Add folder")
                }
                .padding(.trailing, 10)
            } else {
                projectRowRepoTrailingActions(
                    project: project,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isPinned: isPinned
                )
                .padding(.trailing, 10)
            }
        }
        .background(sidebarRowChrome(isSelected: isSelected, isHovered: isHovered))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .id("\(project.id)-\(isPinned ? "pinned" : "unpinned")")
        .animation(
            CodebookMotion.sidebarChrome,
            value: "\(project.id)|\(isSelected)|\(isHovered)|\(isPinned)"
        )
        .onHover { hovering in
            hoveredProjectRowID = hovering ? project.id : nil
        }

        .contextMenu {
            if project.id != "all-projects" {
                Button(model.isProjectPinned(project.id) ? "Unpin" : "Pin") {
                    withAnimation(CodebookMotion.sidebarChrome) {
                        model.togglePinnedProject(project.id)
                    }
                }
                Button("Hide") {
                    withAnimation(CodebookMotion.sidebarList) {
                        model.hideProject(project.id)
                    }
                }
                if project.isManual, let path = project.path {
                    Button("Remove Folder", role: .destructive) {
                        withAnimation(CodebookMotion.sidebarList) {
                            model.removeManualFolder(path)
                        }
                    }
                }
            }
        }
    }
}
