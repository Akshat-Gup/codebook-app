import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.controlActiveState) var controlActiveState
    @AppStorage("codebook.hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("codebook.hasRecordedOnboardingDecision") var hasRecordedOnboardingDecision = false
    @State var copiedPromptID: String?
    @State var dashboardChartStyle: DashboardChartStyle = .heatmap
    @State var barChartRange: BarChartRange = .month
    @State var showSharePopover = false
    @State var copiedShareCaption = false
    /// Per-provider dashboard cards: Bars vs Squares (matches main Activity control).
    @State var providerDashboardChartStyles: [IntegrationProvider: DashboardChartStyle] = [:]
    @State var providerShareItem: ProviderShareItem?
    @State var copiedProviderShare: IntegrationProvider?
    @State var collapsedFirstDay = false
    @State var isSearchFieldFocused = false
    @State var showingHistoryDateRangePopover = false
    @State var historyDraftStartDate: Date?
    @State var historyDraftEndDate: Date?
    @State var historyDisplayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State var hoveredProjectRowID: String?
    @State var hoveredInsightsProjectID: String?
    @State var hoveredMiniChartProvider: IntegrationProvider?
    @State var hoveredBarDate: Date?
    @State var hoveredBarTooltipPosition: CGPoint?
    /// Days to shift the Squares viewport earlier within `ActivityHeatmapPan.historyDayCount`.
    @State var heatmapWindowEndOffset: Int = 0
    /// Pans the **Bars** window along the same `heatmapStats` series as Squares.
    @State var barChartWindowEndOffset: Int = 0
    /// Per-source window for provider card heatmaps (history is longer than the visible slice).
    @State var providerHeatmapOffsets: [IntegrationProvider: Int] = [:]
    @State var dashboardDerivedData = DashboardDerivedData.empty
    @State var automationProjectID: String?
    @State var expandedSessionDayIDs: Set<String> = []
    @State var showSessionWatcherOptions = false

    // MARK: - Project toolbar popover state
    @State var showProjectSkillsPopover = false
    /// Skill sheet must use root-level `.sheet`; target state lives here (not nested in split panes).
    @State var skillSettingsTarget: EcosystemPackage?
    @State var showAutomationsSheet = false
    @State var showAgentsMDSheet = false
    @State var showProjectActivitySheet = false
    @State var showDiagramSheet = false
    /// Export organization mode chosen in the automations popup before the store is created.
    @State var automationExportMode: RepoAutomationExportMode = .date
    @State var showCreatePromptsSetup = false
    /// Agents.md AI analysis result text.
    @State var agentsAIAnalysisResult: String?
    @State var agentsAIAnalysisRunning = false
    /// Which instruction file to preview in the agents sheet.
    @State var agentsFileTab: AgentsFileTab = .agentsMD

    /// Full-history Activity heatmap: longer series + fixed ~6mo viewport (original Squares density).
    enum ActivityHeatmapPan {
        static let historyDayCount = 365
        static let viewportDayCount = 182
        static let stepDayCount = 28
        /// Matches month label row height inside `DashboardHeatmap` (chevron rails align with grid only).
        static let monthHeaderGutter: CGFloat = 20
        /// Keep in sync with `DashboardHeatmap` non-compact grid height.
        static let gridHeight: CGFloat = 248
    }

    enum ProviderCardHeatmap {
        static let historyDayCount = 90
        static let panStepDays = 7
    }

    enum ClipboardHeatmapShare {
        static let maxWeeks = 8
    }

    /// Narrow edge rails — `origin/main`-style chart-first layout with minimal chrome.
    enum DashboardPanRailSize {
        case hero
        case compactStrip

        var width: CGFloat {
            switch self {
            case .hero: return 18
            case .compactStrip: return 14
            }
        }

        func chevronPointSize(stripHeight: CGFloat) -> CGFloat {
            switch self {
            case .hero:
                return 11
            case .compactStrip:
                return min(max(stripHeight * 0.145, 8.5), 10)
            }
        }

        var chevronWeight: Font.Weight {
            switch self {
            case .hero: return .medium
            case .compactStrip: return .semibold
            }
        }
    }

    /// Bar chart plot height (matches pre–pan-rails `origin/main` Activity chart).
    static let heroBarChartPlotHeight: CGFloat = 240

    @State var automationProjectStatus: RepoAutomationStatus?
    @State var promptStoreConfirmation: PromptStoreConfirmationRequest?
    @State var projectActivityChartStyle: DashboardChartStyle = .heatmap
    @State var copiedProjectActivityShare = false
    @State var projectActivityHeatmapOffset: Int = 0
    @State var hoveredActivityBarDay: Date?

    /// Drives animated transitions when the main split-pane layout identity changes.
    var mainPaneLayoutKey: String {
        if model.isDashboardSelected && model.searchText.isEmpty { return "dashboard" }
        if model.isInsightsSelected { return "insights" }
        if model.isSavedSelected { return "saved" }
        if model.isAutomationsSelected { return "sessions" }
        if model.isEcosystemSelected { return "ecosystem" }
        if model.isHiddenProjectsSelected { return "hidden" }
        return "history-\(model.searchText.isEmpty ? "browse" : "search")"
    }

    var mainPaneTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.988, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.004, anchor: .center))
        )
    }

    @ViewBuilder
    var refreshProgressBar: some View {
        if let progress = model.loadingProgress {
            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    var refreshStatusText: String {
        model.loadingStatusText ?? "Scanning prompt history…"
    }

    @ViewBuilder
    func loadingStateView(compact: Bool = false) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            refreshProgressBar
            Text(refreshStatusText)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 0 : 20)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                .background(Color(nsColor: .controlBackgroundColor))
                .hSplitPaneTrailingResizeCursorStrip()

            if model.isDashboardSelected && model.searchText.isEmpty {
                dashboardDetail
                    .frame(minWidth: 700, idealWidth: 1120, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else if model.isInsightsSelected {
                insightsPane
                    .frame(minWidth: 500, idealWidth: 700, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else if model.isSavedSelected {
                savedPane
                    .frame(minWidth: 360, idealWidth: 480, maxWidth: .infinity)
                    .hSplitPaneTrailingResizeCursorStrip()
                    .transition(mainPaneTransition)

                detailPane
                    .frame(minWidth: 420, idealWidth: 620, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else if model.isAutomationsSelected {
                sessionsPane
                    .frame(minWidth: 860, idealWidth: 1120, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else if model.isEcosystemSelected {
                EcosystemPane()
                    .environmentObject(model)
                    .frame(minWidth: 860, idealWidth: 1120, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else if model.isHiddenProjectsSelected {
                hiddenProjectsPane
                    .frame(minWidth: 360, idealWidth: 480, maxWidth: .infinity)
                    .hSplitPaneTrailingResizeCursorStrip()
                    .transition(mainPaneTransition)

                detailPane
                    .frame(minWidth: 420, idealWidth: 620, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            } else {
                historyPane
                    .frame(minWidth: 360, idealWidth: 480, maxWidth: .infinity)
                    .hSplitPaneTrailingResizeCursorStrip()
                    .transition(mainPaneTransition)

                detailPane
                    .frame(minWidth: 420, idealWidth: 620, maxWidth: .infinity)
                    .hSplitPaneLeadingResizeCursorStrip()
                    .transition(mainPaneTransition)
            }
        }
        .animation(CodebookMotion.pane, value: mainPaneLayoutKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.settingsPresented) {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 640)
                .frame(idealWidth: 1040, idealHeight: 680)
        }
        .sheet(item: $promptStoreConfirmation) { request in
            PromptStoreConfirmationSheet(
                request: request,
                confirm: {
                    Task {
                        await performPromptStoreConfirmation(request)
                    }
                },
                cancel: {
                    promptStoreConfirmation = nil
                }
            )
            .frame(width: 460, height: 320)
        }
        .sheet(item: $skillSettingsTarget) { skill in
            SkillProviderSettingsSheet(skill: skill, targets: model.ecosystemGlobalInstallTargets)
                .environmentObject(model)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented {
                    hasCompletedOnboarding = true
                }
            }
        )) {
            OnboardingView(
                startSetup: {
                    hasCompletedOnboarding = true
                    DispatchQueue.main.async {
                        model.settingsPresented = true
                    }
                },
                finish: {
                    hasCompletedOnboarding = true
                }
            )
            .frame(width: 860, height: 560)
        }
        .alert("Error", isPresented: Binding(get: {
            model.errorMessage != nil
        }, set: { value in
            if !value { model.errorMessage = nil }
        })) {
            Button("Dismiss", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.selectedProjectID) { _, _ in
            collapsedFirstDay = false
        }
        .onChange(of: showingHistoryDateRangePopover) { _, isPresented in
            if isPresented {
                syncHistoryRangeSelectionFromModel()
            }
        }
        .onAppear {
            markExistingUsersOnboardedIfNeeded()
            rebuildDashboardDerivedData()
        }
        .onChange(of: model.importedPromptsRevision) { _, _ in
            rebuildDashboardDerivedData()
        }
    }

    func markExistingUsersOnboardedIfNeeded() {
        guard !hasRecordedOnboardingDecision else { return }
        hasRecordedOnboardingDecision = true

        let hasExistingAppState =
            !model.importedPrompts.isEmpty ||
            !model.manualFolders.isEmpty ||
            !model.pinnedProjectIDs.isEmpty ||
            !model.savedPromptIDs.isEmpty ||
            !model.savedPromptKeys.isEmpty ||
            !model.customProviderProfiles.isEmpty ||
            !model.savedDiagrams.isEmpty

        if hasExistingAppState {
            hasCompletedOnboarding = true
        }
    }
}
