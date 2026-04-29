import AppKit
import SwiftUI

// MARK: - Skill scope toggle (Overall vs Project)

private enum SkillScope: String, CaseIterable, Hashable {
    case overall
    case project

    var title: String {
        switch self {
        case .overall: return "All Skills"
        case .project: return "Project Skills"
        }
    }
}

// MARK: - Filter kind for pill bar

private enum PluginFilterKind: String, CaseIterable, Hashable {
    case all
    case mcp
    case skill
    case plugin

    var title: String {
        switch self {
        case .all: return "All"
        case .mcp: return "MCP"
        case .skill: return "Skill"
        case .plugin: return "Plugin"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .mcp: return "server.rack"
        case .skill: return "sparkles"
        case .plugin: return "puzzlepiece.extension"
        }
    }

    func matches(_ kind: EcosystemPackageKind) -> Bool {
        switch self {
        case .all: return true
        case .mcp: return kind == .mcp
        case .skill: return kind == .skill
        case .plugin: return kind == .plugin
        }
    }

    var searchKind: EcosystemPackageKind? {
        switch self {
        case .all: return nil
        case .skill: return .skill
        case .mcp: return .mcp
        case .plugin: return .plugin
        }
    }
}

// MARK: - Shared card chrome

private enum PluginCardChrome {
    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let iconSize: CGFloat = 36

    /// Adaptive border tint that works in both light and dark modes.
    static var borderTint: Color { Color.primary.opacity(0.08) }
    /// Adaptive shadow colour for both appearances.
    static var shadowTint: Color { Color.primary.opacity(0.06) }

    @ViewBuilder
    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderTint, lineWidth: 0.5)
            )
            .shadow(color: shadowTint, radius: 3, y: 1.5)
    }

    @ViewBuilder
    static func glassBackground() -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderTint, lineWidth: 0.5)
            )
            .shadow(color: shadowTint, radius: 4, y: 2)
    }
}

// MARK: - Install control (split: primary install + destinations menu)

private struct EcosystemGlassySplitInstallBar<MenuContent: View>: View {
    @EnvironmentObject private var model: AppModel
    let isInstalledGlobally: Bool
    var hasSelectedTargets: Bool? = nil
    /// Tighter metrics for installed-card status row.
    var compact: Bool = false
    let onInstall: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    private var primaryDisabled: Bool {
        isInstalledGlobally || !(hasSelectedTargets ?? !model.ecosystemInstallTargetSelection.isEmpty)
    }

    /// Fixed cross-axis height so the primary `Button` and `Menu` halves always match (avoids per-row sizing drift).
    private var barHeight: CGFloat { compact ? 32 : 40 }
    private var verticalPadding: CGFloat { compact ? 4 : 8 }
    private var iconSize: CGFloat { compact ? 11 : 12 }
    private var titleFont: Font { compact ? .subheadline.weight(.semibold) : .system(size: 13, weight: .semibold) }
    /// Menu segment width — shared by Install and Installed so spacing stays consistent.
    private var menuTrayWidth: CGFloat { compact ? 30 : 34 }
    private var cornerRadius: CGFloat { compact ? 8 : 10 }
    private var installFillColor: Color { Color(nsColor: .systemBlue) }

    private var menuChevronColor: Color {
        isInstalledGlobally ? .secondary : .white
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onInstall) {
                HStack(spacing: compact ? 6 : 8) {
                    Spacer(minLength: 0)
                    Image(systemName: isInstalledGlobally ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: iconSize, weight: .semibold))
                    Text(isInstalledGlobally ? "Installed" : "Install")
                        .font(titleFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isInstalledGlobally ? Color.secondary : Color.white)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, compact ? 6 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)

            Menu {
                menuContent()
            } label: {
                menuLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(menuChevronColor)
            .frame(width: menuTrayWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(height: barHeight)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isInstalledGlobally ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(installFillColor))
                .overlay {
                    if isInstalledGlobally {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isInstalledGlobally ? Color(nsColor: .separatorColor) : Color.primary.opacity(0.10),
                            lineWidth: 0.5
                        )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.primary.opacity(0.10), radius: 2, y: 1)
    }

    private var menuLabel: some View {
        GeometryReader { geo in
            Image(systemName: "chevron.down")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(menuChevronColor)
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
        }
        .frame(width: menuTrayWidth, height: barHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Root pane

struct EcosystemPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchQuery: String = ""
    @State private var activeFilter: PluginFilterKind = .all
    @State private var showNewSkillSheet = false
    @State private var showURLInstallSheet = false
    @State private var skillScope: SkillScope = .overall
    @State private var selectedProjectFilterID: String? = nil
    /// Whether a remote search has been submitted (prevents showing "No results" on initial empty state).
    @State private var hasSubmittedSearch = false

    private static let pluginCatalogSpacing: CGFloat = 14
    private static let pluginCatalogColumnCount = 3
    private static let pluginCatalogCardWidth: CGFloat = 292
    private static let topControlHeight: CGFloat = 46
    private static let maxContentWidth: CGFloat =
        (pluginCatalogCardWidth * CGFloat(pluginCatalogColumnCount)) +
        (pluginCatalogSpacing * CGFloat(pluginCatalogColumnCount - 1))

    /// At least three equal columns for suggested and installed catalog cards.
    private static let pluginCatalogGridColumns: [GridItem] = Array(
        repeating: GridItem(
            .flexible(minimum: pluginCatalogCardWidth),
            spacing: pluginCatalogSpacing,
            alignment: .top
        ),
        count: pluginCatalogColumnCount
    )

    private var projectScopedTargets: [ProviderInstallDestination] {
        model.ecosystemInstallTargets.filter { !$0.isBuiltIn }
    }

    private var projectFilterProjects: [ProjectSummary] {
        model.localChangesProjectOptions
    }

    private var visibleInstallTargets: [ProviderInstallDestination] {
        switch skillScope {
        case .overall:
            return model.ecosystemGlobalInstallTargets
        case .project:
            if let selectedProject = selectedProjectSummary,
               let target = projectInstallTarget(for: selectedProject) {
                return [target]
            }
            return []
        }
    }

    private var effectiveInstallTargetSelection: Set<String> {
        switch skillScope {
        case .overall:
            return model.ecosystemInstallTargetSelection
        case .project:
            let scoped = Set(visibleInstallTargets.map(\.id))
            return scoped.isEmpty ? Set(model.ecosystemInstallTargetSelection) : scoped
        }
    }

    private var filteredCatalog: [EcosystemPackage] {
        let base = model.ecosystemCatalog.filter { activeFilter.matches($0.kind) }
        if skillScope == .project {
            return base.filter { $0.kind == .skill }
        }
        return base
    }

    /// Catalog entries matching the current search query (local filter).
    private var localSearchFilteredCatalog: [EcosystemPackage] {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return filteredCatalog }
        let q = searchQuery.lowercased()
        return filteredCatalog.filter {
            $0.name.lowercased().contains(q)
            || $0.id.lowercased().contains(q)
            || $0.summary.lowercased().contains(q)
            || $0.kind.rawValue.lowercased().contains(q)
            || $0.supportedProviders.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var suggestedPackages: [EcosystemPackage] {
        let targets = visibleInstallTargets
        return localSearchFilteredCatalog.filter { package in
            !targets.contains { target in
                model.isEcosystemPackageInstalled(package, targetID: target.id)
            }
        }
    }

    private var installedPackages: [EcosystemPackage] {
        let targets = visibleInstallTargets
        let fromCatalog = localSearchFilteredCatalog.filter { package in
            targets.contains { target in
                model.isEcosystemPackageInstalled(package, targetID: target.id)
            }
        }
        let discovered: [EcosystemPackage] = {
            let base = skillScope == .overall
                ? model.ecosystemDiscoveredInstalledPackages.filter { pkg in activeFilter.matches(pkg.kind) }
                : []
            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
            let q = searchQuery.lowercased()
            return base.filter {
                $0.name.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.kind.rawValue.lowercased().contains(q)
                || $0.supportedProviders.contains(where: { $0.lowercased().contains(q) })
            }
        }()
        let catalogKeys = Set(fromCatalog.map { "\($0.kind.rawValue)|\(Slug.make(from: $0.name))" })
        let onlyOnDisk = discovered.filter { entry in
            !catalogKeys.contains("\(entry.kind.rawValue)|\(Slug.make(from: entry.name))")
        }
        let merged = fromCatalog + onlyOnDisk
        return merged.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)

                // Search + add row
                HStack(spacing: 10) {
                    searchBar
                    addMenu
                }
                .padding(.bottom, 14)

                // Filter pills
                filterPills
                    .padding(.bottom, 20)

                if skillScope == .project {
                    projectFilters
                        .padding(.bottom, 20)
                }

                if let summary = model.ecosystemSearchSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { PluginCardChrome.glassBackground() }
                        .padding(.bottom, 16)
                }

                if model.ecosystemSearchIsRunning {
                    HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }
                        .padding(.top, 60)
                } else if !model.ecosystemSearchResults.isEmpty {
                    sectionHeader("Results")
                        .padding(.bottom, 10)
                    LazyVGrid(columns: Self.pluginCatalogGridColumns, spacing: Self.pluginCatalogSpacing) {
                        ForEach(model.ecosystemSearchResults) { result in
                            resultRow(result)
                        }
                    }

                    if !searchQuery.isEmpty {
                        // Also show local catalog matches alongside remote results
                        catalogContent
                    }
                } else if hasSubmittedSearch && !searchQuery.isEmpty && model.ecosystemSearchResults.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.quaternary)
                        Text("No results for \u{201C}\(searchQuery)\u{201D}")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Check the spelling or try a new search.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                    // Still show local catalog matches
                    catalogContent
                } else {
                    catalogContent
                }
            }
            .frame(maxWidth: Self.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewSkillSheet) {
            NewSkillSheet(isPresented: $showNewSkillSheet).environmentObject(model)
        }
        .sheet(isPresented: $showURLInstallSheet) {
            URLInstallSheet(isPresented: $showURLInstallSheet).environmentObject(model)
        }
    }

    // MARK: Catalog sections

    @ViewBuilder
    private var catalogContent: some View {
        if !suggestedPackages.isEmpty {
            sectionHeader("Suggested")
                .padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.pluginCatalogSpacing) {
                    ForEach(suggestedPackages) { package in
                        PluginPackageCard(
                            package: package,
                            variant: .suggested,
                            installTargetIDs: effectiveInstallTargetSelection,
                            isInstalledInActiveTargets: visibleInstallTargets.contains { target in
                                model.isEcosystemPackageInstalled(package, targetID: target.id)
                            }
                        ) {
                            providerToggles
                        }
                        .environmentObject(model)
                        .frame(width: Self.pluginCatalogCardWidth)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -32)
            .padding(.leading, 32)
            .padding(.bottom, 24)
        }

        if !installedPackages.isEmpty {
            sectionHeader("Installed")
                .padding(.bottom, 10)
            LazyVGrid(columns: Self.pluginCatalogGridColumns, spacing: Self.pluginCatalogSpacing) {
                ForEach(installedPackages) { package in
                    PluginPackageCard(
                        package: package,
                        variant: .installed,
                        installTargetIDs: effectiveInstallTargetSelection,
                        isInstalledInActiveTargets: visibleInstallTargets.contains { target in
                            model.isEcosystemPackageInstalled(package, targetID: target.id)
                        }
                    ) {
                        EmptyView()
                    }
                    .environmentObject(model)
                }
            }
        }

        if suggestedPackages.isEmpty && installedPackages.isEmpty && model.ecosystemSearchResults.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.quaternary)
                Text("No plugins match this filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Text("Plugins")
                .font(.largeTitle.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            // Skill scope toggle
            HStack(spacing: 0) {
                ForEach(SkillScope.allCases, id: \.self) { scope in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            skillScope = scope
                        }
                    } label: {
                        Text(scope.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(skillScope == scope ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(skillScope == scope ? Color(nsColor: .controlBackgroundColor) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
            )
        }
    }

    @ViewBuilder
    private var projectFilters: some View {
        if projectFilterProjects.isEmpty {
            Text("No scanned projects are available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    projectFilterChip(title: "All Projects", count: projectFilterProjects.count, isActive: selectedProjectFilterID == nil) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                            selectedProjectFilterID = nil
                        }
                    }

                    ForEach(projectFilterProjects, id: \.id) { project in
                        projectFilterChip(
                            title: project.name,
                            count: project.promptCount,
                            isActive: selectedProjectFilterID == project.id
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                selectedProjectFilterID = project.id
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Add menu (+ button)

    private var addMenu: some View {
        Menu {
            Button { showNewSkillSheet = true } label: {
                Label("Create Skill", systemImage: "doc.badge.plus")
            }
            Button { showURLInstallSheet = true } label: {
                Label("Add Your Own", systemImage: "link")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: Self.topControlHeight)
        }
        .menuStyle(.borderlessButton)
        .frame(width: Self.topControlHeight, height: Self.topControlHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: Color.primary.opacity(0.06), radius: 2, y: 1)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Group {
                if model.ecosystemSearchIsRunning {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .frame(width: 22)

            TextField("Search skills, plugins, MCP servers\u{2026}", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .onChange(of: searchQuery) {
                    hasSubmittedSearch = false
                    model.clearEcosystemSearch()
                }
                .onSubmit {
                    hasSubmittedSearch = true
                    Task { await model.searchEcosystemGitHub(query: searchQuery, kind: activeFilter.searchKind) }
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    hasSubmittedSearch = false
                    model.clearEcosystemSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: Self.topControlHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: Color.primary.opacity(0.06), radius: 2, y: 1)
        }
    }

    // MARK: Filter pills (glassy selector)

    private var filterPills: some View {
        HStack(spacing: 0) {
            ForEach(PluginFilterKind.allCases, id: \.self) { filter in
                let isActive = activeFilter == filter
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { activeFilter = filter }
                    if hasSubmittedSearch, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await model.searchEcosystemGitHub(query: searchQuery, kind: filter.searchKind) }
                    }
                } label: {
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isActive ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor)
                                    .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 2)
                            }
                        }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.primary.opacity(0.06), radius: 3, y: 1.5)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    // MARK: GitHub result row

    private func resultRow(_ result: GitHubPackageSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(result.kind.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("\(result.stars)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let url = URL(string: result.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
                .help("Open on GitHub")
            }

            Text(result.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !result.topics.isEmpty || result.language != nil {
                HStack(spacing: 6) {
                    if let lang = result.language { kindPill(lang) }
                    ForEach(result.topics.prefix(3), id: \.self) { topic in kindPill(topic) }
                }
            }

            Spacer(minLength: 0)

            searchResultInstallBar(result: result)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PluginCardChrome.cardBackground() }
    }

    // MARK: Install bar for search results

    private func searchResultInstallBar(result: GitHubPackageSearchResult) -> some View {
        let installedGlobally = visibleInstallTargets.contains { target in
            model.isEcosystemPackageInstalled(result.sourcePackage, targetID: target.id)
        }
        return EcosystemGlassySplitInstallBar(
            isInstalledGlobally: installedGlobally,
            hasSelectedTargets: !effectiveInstallTargetSelection.isEmpty,
            onInstall: {
            Task {
                await model.installGitHubPackage(
                    urlString: result.url,
                    kind: result.kind,
                    targetIDs: effectiveInstallTargetSelection
                )
            }
        }) {
            providerToggles
        }
        .environmentObject(model)
    }

    @ViewBuilder
    private var providerToggles: some View {
        let targets = skillScope == .project ? visibleInstallTargets : model.ecosystemInstallTargets
        if skillScope == .project {
            Section("Install into") {
                ForEach(targets, id: \.id) { target in
                    Label(target.name, systemImage: target.systemImage)
                }
            }
        } else {
            Section("Install into") {
                ForEach(targets, id: \.id) { target in
                    let id = target.id
                    Toggle(isOn: Binding(
                        get: { model.ecosystemInstallTargetSelection.contains(id) },
                        set: { on in model.toggleEcosystemInstallTarget(id: id, enabled: on) }
                    )) {
                        Label(target.name, systemImage: target.systemImage)
                    }
                }
                Button("All destinations") { model.selectAllEcosystemInstallTargets() }
            }
        }
    }

    private func kindPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var selectedProjectSummary: ProjectSummary? {
        guard let selectedProjectFilterID else { return nil }
        return projectFilterProjects.first(where: { $0.id == selectedProjectFilterID })
    }

    private func projectInstallTarget(for project: ProjectSummary) -> ProviderInstallDestination? {
        guard let path = project.path else { return nil }
        let normalizedProjectPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return projectScopedTargets.first { target in
            URL(fileURLWithPath: target.rootPath).standardizedFileURL.path == normalizedProjectPath
        }
    }

    private func projectFilterChip(title: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? Color.white.opacity(0.92) : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(isActive ? Color.white.opacity(0.18) : Color.primary.opacity(0.06))
                    }
            }
            .foregroundStyle(isActive ? Color.white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: isActive ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.05), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Package card (suggested + installed)

private struct PluginPackageCard<ProviderMenu: View>: View {
    enum Variant: Hashable {
        case suggested
        case installed
    }

    @EnvironmentObject private var model: AppModel
    @State private var showDeleteSheet = false
    let package: EcosystemPackage
    let variant: Variant
    let installTargetIDs: Set<String>
    let isInstalledInActiveTargets: Bool
    @ViewBuilder private let providerMenu: () -> ProviderMenu

    init(
        package: EcosystemPackage,
        variant: Variant,
        installTargetIDs: Set<String>,
        isInstalledInActiveTargets: Bool,
        @ViewBuilder providerMenu: @escaping () -> ProviderMenu
    ) {
        self.package = package
        self.variant = variant
        self.installTargetIDs = installTargetIDs
        self.isInstalledInActiveTargets = isInstalledInActiveTargets
        self.providerMenu = providerMenu
    }

    private var installedTargets: [ProviderInstallDestination] {
        model.ecosystemInstallTargets.filter { model.isEcosystemPackageInstalled(package, targetID: $0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: package.kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.headline)
                        .lineLimit(1)
                    kindBadge(package.kind)
                }

                Spacer(minLength: 0)
            }

            Text(package.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            bottomChrome
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background { PluginCardChrome.cardBackground() }
        .sheet(isPresented: $showDeleteSheet) {
            DeleteInstalledPackageSheet(
                isPresented: $showDeleteSheet,
                package: package,
                installedTargets: installedTargets
            )
            .environmentObject(model)
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        switch variant {
        case .suggested:
            EcosystemGlassySplitInstallBar(
                isInstalledGlobally: isInstalledInActiveTargets,
                hasSelectedTargets: !installTargetIDs.isEmpty,
                onInstall: {
                Task { await model.installEcosystemPackage(package, targetIDs: installTargetIDs) }
            }) {
                providerMenu()
            }
        case .installed:
            HStack(alignment: .center, spacing: 8) {
                EcosystemGlassySplitInstallBar(isInstalledGlobally: true, compact: true, onInstall: {}) {
                    Section("Installed in") {
                        ForEach(model.ecosystemInstallTargets, id: \.id) { target in
                            let installed = model.isEcosystemPackageInstalled(package, targetID: target.id)
                            if installed {
                                Label {
                                    Text(target.name)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            } else {
                                Button {
                                    var targets = model.ecosystemInstallTargetSelection
                                    targets.insert(target.id)
                                    model.updateEcosystemInstallTargetSelection(targets)
                                    Task { await model.installEcosystemPackage(package, targetIDs: [target.id]) }
                                } label: {
                                    Text(target.name)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                settingsButton
            }
        }
    }

    private var shareButton: some View {
        Button {
            let text = "Check out \"\(package.name)\" – \(package.summary)"
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } label: {
            iconActionChrome(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .help("Copy share text to clipboard")
    }

    private var settingsButton: some View {
        Button {
            showDeleteSheet = true
        } label: {
            iconActionChrome(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Manage or delete this installed package")
    }

    private func iconActionChrome(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: Color.primary.opacity(0.06), radius: 3, y: 1.5)
            }
    }

    private func kindBadge(_ kind: EcosystemPackageKind) -> some View {
        Text(kind.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
    }
}

private struct DeleteInstalledPackageSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    let package: EcosystemPackage
    let installedTargets: [ProviderInstallDestination]

    private var allTargets: [ProviderInstallDestination] {
        model.ecosystemInstallTargets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close button
            HStack(alignment: .center) {
                Image(systemName: package.kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.headline)
                    Text(package.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 24)

            // Provider list
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Installed Providers")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)

                    ForEach(allTargets, id: \.id) { target in
                        providerRow(target)
                            .padding(.horizontal, 24)
                    }
                }
            }

            Divider().padding(.horizontal, 24)

            // Bottom actions
            HStack(spacing: 10) {
                Button {
                    model.revealInstalledPackageInFinder(package)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(installedTargets.isEmpty)

                Spacer()

                Button {
                    Task {
                        let ids = Set(installedTargets.map(\.id))
                        await model.uninstallEcosystemPackage(package, targetIDs: ids)
                        await MainActor.run { isPresented = false }
                    }
                } label: {
                    Label("Uninstall All", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(installedTargets.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 440, height: 380, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func providerRow(_ target: ProviderInstallDestination) -> some View {
        let isInstalled = model.isEcosystemPackageInstalled(package, targetID: target.id)

        HStack(spacing: 12) {
            Image(systemName: target.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isInstalled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isInstalled ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                }

            Text(target.name)
                .font(.subheadline)
                .foregroundStyle(isInstalled ? .primary : .secondary)

            Spacer()

            if isInstalled {
                Button {
                    Task { await model.uninstallEcosystemPackage(package, targetIDs: [target.id]) }
                } label: {
                    Text("Remove")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                        }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await model.installEcosystemPackage(package, targetIDs: [target.id]) }
                } label: {
                    Text("Install")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
    }
}

// MARK: - New skill sheet

private struct NewSkillSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var summary: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Skill").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                TextField("Skill name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Short summary", text: $summary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Button("Create") {
                    Task {
                        await model.createCustomSkill(
                            name: name, summary: summary,
                            targetIDs: model.ecosystemInstallTargetSelection
                        )
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.ecosystemInstallTargetSelection.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - URL install sheet

private struct URLInstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var url: String = ""
    @State private var kind: EcosystemPackageKind = .skill

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Install from URL").font(.title2.weight(.semibold))
            TextField("https://github.com/owner/repo", text: $url).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $kind) {
                ForEach(EcosystemPackageKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Button("Install") {
                    Task {
                        await model.installGitHubPackage(
                            urlString: url, kind: kind,
                            targetIDs: model.ecosystemInstallTargetSelection
                        )
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.ecosystemInstallTargetSelection.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
