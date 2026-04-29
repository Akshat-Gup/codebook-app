import SwiftUI
import Charts

extension ContentView {

    // MARK: - Dashboard

    var dashboardDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardHeroCard

                // Stats row
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    ForEach(dashboardMetrics) { metric in
                        statCard(
                            title: metric.title,
                            value: metric.value,
                            trailingValue: metric.trailingValue,
                            subtitle: metric.subtitle
                        )
                    }
                }

                // Provider mini-charts
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                    ForEach(providerMiniCharts) { data in
                        providerMiniChart(data: data)
                    }
                }
                .popover(item: $providerShareItem) { item in
                    Group {
                        if let popoverData = providerMiniCharts.first(where: { $0.provider == item.provider }) {
                            providerSharePopoverContent(data: popoverData)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var dashboardHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("Activity")
                    .font(.title.weight(.semibold))

                Spacer()

                Button {
                    copyDashboardShareCaption()
                    showSharePopover = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text(copiedShareCaption ? "Copied" : "Share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(AppControlChrome.charcoal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        AppControlChrome.glassShareButtonBackground(cornerRadius: 10)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSharePopover) {
                    sharePopoverContent
                }
            }

            // Trailing cluster (right-aligned): date range → 7d picker → Bars/Squares.
            HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)

                if let heroDateLabel = heroActivityDateRangeLabel {
                    Text(heroDateLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                }

                if dashboardChartStyle == .bars {
                    AppSegmentedControl(
                        selection: $barChartRange,
                        options: Array(BarChartRange.allCases),
                        title: { $0.title }
                    )
                    .fixedSize()
                }

                DashboardHeroChartStyleControl(selection: $dashboardChartStyle)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: barChartRange) { _, _ in
                clampHeatmapWindowOffset()
                clampBarChartWindowOffset()
                clampProviderHeatmapOffsets()
            }

            dashboardHeroChartCrossfade
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Crossfade between bar chart and heatmap (opacity only avoids hover/layout jump from scale/offset).
    var dashboardHeroChartCrossfade: some View {
        let style = dashboardChartStyle
        /// Fixed height per style so the hidden mode doesn’t force extra vertical space (see `ZStack` sizing).
        let slotHeight = Self.heroActivityCrossfadeHeight(for: style)
        return ZStack(alignment: .top) {
            recentActivityBarChart
                .frame(maxWidth: .infinity)
                .opacity(style == .bars ? 1 : 0)
                .allowsHitTesting(style == .bars)

            recentActivityHeatmap
                .frame(maxWidth: .infinity)
                .opacity(style == .heatmap ? 1 : 0)
                .allowsHitTesting(style == .heatmap)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: slotHeight, alignment: .top)
        .padding(.top, 4)
        .padding(.horizontal, 0)
        .padding(.bottom, 2)
        .animation(CodebookMotion.chartStyleSwap, value: dashboardChartStyle)
    }

    static func heroActivityCrossfadeHeight(for style: DashboardChartStyle) -> CGFloat {
        switch style {
        case .bars:
            return heroBarChartPlotHeight + 16
        case .heatmap:
            return DashboardHeatmap.heroLayoutTotalHeight + 36
        }
    }

    var heroActivityDateRangeLabel: String? {
        switch dashboardChartStyle {
        case .bars:
            guard let first = barStats.first?.day, let last = barStats.last?.day else { return nil }
            return heatmapWindowRangeLabel(from: first, to: last)
        case .heatmap:
            guard let first = heatmapVisibleStats.first?.day, let last = heatmapVisibleStats.last?.day else { return nil }
            return heatmapWindowRangeLabel(from: first, to: last)
        }
    }

    var recentActivityBarChart: some View {
        HStack(alignment: .center, spacing: 4) {
            heatmapPanRail(
                systemName: "chevron.backward",
                disabled: barChartWindowEndOffset >= maxBarChartWindowOffset,
                help: "Earlier period",
                monthHeaderGutter: 0,
                gridHeight: Self.heroBarChartPlotHeight,
                centerChevronInColumn: true,
                railSize: .hero
            ) {
                barChartWindowEndOffset = min(
                    barChartWindowEndOffset + ActivityHeatmapPan.stepDayCount,
                    maxBarChartWindowOffset
                )
            }

            heroBarChartPlot
                .frame(maxWidth: .infinity)

            heatmapPanRail(
                systemName: "chevron.forward",
                disabled: barChartWindowEndOffset <= 0,
                help: "Later period",
                monthHeaderGutter: 0,
                gridHeight: Self.heroBarChartPlotHeight,
                centerChevronInColumn: true,
                railSize: .hero
            ) {
                barChartWindowEndOffset = max(
                    barChartWindowEndOffset - ActivityHeatmapPan.stepDayCount,
                    0
                )
            }
        }
    }

    var heroBarChartPlot: some View {
        Chart(barStats) { stat in
            BarMark(
                x: .value("Day", stat.day, unit: .day),
                y: .value("Prompts", stat.count)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(
                LinearGradient(
                    colors: [dashboardHighlight.opacity(0.96), dashboardAccent.opacity(0.84)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )

            if let hoveredBarDate,
               Calendar.current.isDate(stat.day, inSameDayAs: hoveredBarDate) {
                RuleMark(x: .value("Day", stat.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else {
                                    hoveredBarDate = nil
                                    hoveredBarTooltipPosition = nil
                                    return
                                }
                                let plotAreaFrame = geometry[plotFrame]
                                guard plotAreaFrame.contains(location) else {
                                    hoveredBarDate = nil
                                    hoveredBarTooltipPosition = nil
                                    return
                                }
                                let relativeX = location.x - plotAreaFrame.origin.x
                                hoveredBarDate = barDate(for: relativeX, plotWidth: plotAreaFrame.width)
                                hoveredBarTooltipPosition = location
                            case .ended:
                                hoveredBarDate = nil
                                hoveredBarTooltipPosition = nil
                            }
                        }

                    if let hoveredStat = hoveredBarStat, let pos = hoveredBarTooltipPosition {
                        barChartHoverTooltip(for: hoveredStat)
                            .position(
                                x: min(max(pos.x, 80), max(geometry.size.width - 80, 80)),
                                y: max(pos.y - 52, 10)
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: Self.heroBarChartPlotHeight)
        .padding(.horizontal, 0)
        .chartXAxis {
            barChartXAxis(range: barChartRange, gridOpacity: 0.12)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(CodebookMotion.chartPlotHover, value: hoveredBarDate)
    }

    var hoveredBarStat: DailyPromptStat? {
        guard let hoveredBarDate else { return nil }
        return barStats.first(where: { Calendar.current.isDate($0.day, inSameDayAs: hoveredBarDate) })
    }

    func barDate(for relativeX: CGFloat, plotWidth: CGFloat) -> Date? {
        guard !barStats.isEmpty, plotWidth > 0 else { return nil }
        let clampedX = min(max(relativeX, 0), plotWidth)
        let step = plotWidth / CGFloat(barStats.count)
        let index = min(max(Int(clampedX / max(step, 1)), 0), barStats.count - 1)
        return barStats[index].day
    }

    func barChartHoverTooltip(for stat: DailyPromptStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption.weight(.semibold))
            Text("\(stat.count) \(stat.count == 1 ? "prompt" : "prompts")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    @AxisContentBuilder
    func barChartXAxis(
        range: BarChartRange,
        labelFont: Font? = nil,
        gridOpacity: Double
    ) -> some AxisContent {
        switch range {
        case .week:
            AxisMarks(preset: .automatic, values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(gridOpacity))
                if let labelFont {
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(.secondary)
                }
            }
        case .month:
            AxisMarks(preset: .automatic, values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(gridOpacity))
                if let labelFont {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .foregroundStyle(.secondary)
                }
            }
        case .quarter:
            AxisMarks(preset: .automatic, values: .stride(by: .month, count: 1)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(gridOpacity))
                if let labelFont {
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .foregroundStyle(.secondary)
                }
            }
        case .half:
            AxisMarks(preset: .automatic, values: .stride(by: .month, count: 2)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(gridOpacity))
                if let labelFont {
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var recentActivityHeatmap: some View {
        HStack(alignment: .center, spacing: 4) {
            heatmapPanRail(
                systemName: "chevron.backward",
                disabled: heatmapWindowEndOffset >= maxHeatmapWindowOffset,
                help: "Earlier period",
                monthHeaderGutter: 0,
                gridHeight: DashboardHeatmap.heroLayoutTotalHeight,
                centerChevronInColumn: true,
                railSize: .hero
            ) {
                heatmapWindowEndOffset = min(
                    heatmapWindowEndOffset + ActivityHeatmapPan.stepDayCount,
                    maxHeatmapWindowOffset
                )
            }

            DashboardHeatmap(stats: heatmapVisibleStats, accent: dashboardHighlight)
                .frame(maxWidth: .infinity)

            heatmapPanRail(
                systemName: "chevron.forward",
                disabled: heatmapWindowEndOffset <= 0,
                help: "Later period",
                monthHeaderGutter: 0,
                gridHeight: DashboardHeatmap.heroLayoutTotalHeight,
                centerChevronInColumn: true,
                railSize: .hero
            ) {
                heatmapWindowEndOffset = max(
                    heatmapWindowEndOffset - ActivityHeatmapPan.stepDayCount,
                    0
                )
            }
        }
    }

    /// Full grid-height hit strip (no background); icon scales with vertical space.
    @ViewBuilder
    func heatmapPanRail(
        systemName: String,
        disabled: Bool,
        help: String,
        monthHeaderGutter: CGFloat,
        gridHeight: CGFloat,
        centerChevronInColumn: Bool = false,
        railSize: DashboardPanRailSize = .compactStrip,
        action: @escaping () -> Void
    ) -> some View {
        let railWidth = railSize.width
        let chevronTint = disabled ? Color.secondary.opacity(0.38) : Color.secondary

        if centerChevronInColumn {
            // Offset chevron so it centres on the grid area (skip month-row gutter at top).
            let topGutter: CGFloat = 30  // month row (20) + spacing (10)
            let bottomGutter: CGFloat = gridHeight - topGutter - 248  // legend + spacing
            let verticalBias = (topGutter - max(bottomGutter, 0)) / 2
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(
                        size: railSize.chevronPointSize(stripHeight: gridHeight),
                        weight: railSize.chevronWeight
                    ))
                    .foregroundStyle(chevronTint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: verticalBias)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .help(help)
            .frame(width: railWidth, height: gridHeight)
        } else {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: monthHeaderGutter)
                Button(action: action) {
                    GeometryReader { geo in
                        let s = railSize.chevronPointSize(stripHeight: geo.size.height)
                        Image(systemName: systemName)
                            .font(.system(size: s, weight: railSize.chevronWeight))
                            .foregroundStyle(chevronTint)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(help)
                .frame(width: railWidth, height: gridHeight)
            }
        }
    }

    func clampProviderHeatmapOffsets() {
        let n = min(barChartRange.days, ProviderCardHeatmap.historyDayCount)
        let maxOff = max(0, ProviderCardHeatmap.historyDayCount - n)
        for key in providerHeatmapOffsets.keys {
            providerHeatmapOffsets[key] = min(providerHeatmapOffsets[key, default: 0], maxOff)
        }
    }

    /// Visible slice for provider **bar** charts — follows the dashboard date range and pan offset.
    func providerBarVisibleStats(for data: ProviderMiniChartData) -> [DailyPromptStat] {
        let full = data.historyStats
        let n = min(barChartRange.days, full.count)
        guard !full.isEmpty, n > 0 else { return [] }
        let lastIdx = full.count - 1
        let maxOff = max(0, full.count - n)
        let off = min(providerHeatmapOffsets[data.provider, default: 0], maxOff)
        let windowEndIdx = lastIdx - off
        let windowStartIdx = windowEndIdx - n + 1
        let s = max(0, windowStartIdx)
        let e = min(windowEndIdx, full.count - 1)
        guard s <= e else { return Array(full.suffix(n)) }
        return Array(full[s...e])
    }

    /// Full provider-card history for **Squares** — not tied to the hero bar-chart date toggle.
    func providerCardHeatmapStats(for data: ProviderMiniChartData) -> [DailyPromptStat] {
        let full = data.historyStats
        guard !full.isEmpty else { return [] }
        let n = min(ProviderCardHeatmap.historyDayCount, full.count)
        return Array(full.suffix(n))
    }

    func maxProviderHeatmapOffset(for data: ProviderMiniChartData) -> Int {
        let full = data.historyStats
        let n = min(barChartRange.days, full.count)
        guard !full.isEmpty, n > 0 else { return 0 }
        return max(0, full.count - n)
    }

    func statCard(title: String, value: String, trailingValue: String?, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let trailingValue, !trailingValue.isEmpty {
                    Text(trailingValue)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var providerMiniCharts: [ProviderMiniChartData] {
        dashboardDerivedData.providerMiniCharts
    }

    func providerCardUsesExpandedViewport(for provider: IntegrationProvider) -> Bool {
        guard let index = providerMiniCharts.firstIndex(where: { $0.provider == provider }) else { return false }
        let rowStart = (index / 2) * 2
        let rowEnd = min(rowStart + 2, providerMiniCharts.count)
        return providerMiniCharts[rowStart..<rowEnd].contains { data in
            providerDashboardChartStyles[data.provider, default: .heatmap] == .bars
        }
    }

    func providerMiniChart(data: ProviderMiniChartData) -> some View {
        let style = providerDashboardChartStyles[data.provider, default: .heatmap]
        let rowUsesExpandedViewport = providerCardUsesExpandedViewport(for: data.provider)
        let barStats = providerBarVisibleStats(for: data)
        let providerBarsMaxY = max(barStats.map(\.count).max() ?? 0, 1)
        let providerBarsXDomain: ClosedRange<Date>? = {
            guard let first = barStats.first?.day, let last = barStats.last?.day else { return nil }
            let cal = Calendar.current
            return cal.startOfDay(for: first)...cal.startOfDay(for: last)
        }()
        let heatmapStats = providerCardHeatmapStats(for: data)
        let providerMaxOff = maxProviderHeatmapOffset(for: data)
        let providerOff = min(providerHeatmapOffsets[data.provider, default: 0], providerMaxOff)
        let providerBarDateRangeLabel: String? = {
            guard let first = barStats.first?.day, let last = barStats.last?.day else { return nil }
            return heatmapWindowRangeLabel(from: first, to: last)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 6) {
                    PlatformIconView(provider: data.provider, size: 14)
                    Text(data.provider.title)
                }
                .font(.subheadline.weight(.medium))

                Text(data.total.formatted(.number.grouping(.automatic)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    copyProviderShareCaption(data: data)
                    providerShareItem = ProviderShareItem(provider: data.provider)
                } label: {
                    Image(systemName: copiedProviderShare == data.provider ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(copiedProviderShare == data.provider ? 0.85 : 1))
                        .frame(width: 26, height: 26)
                        .background {
                            AppControlChrome.glassShareButtonBackground(cornerRadius: 6)
                        }
                }
                .buttonStyle(.plain)
                .help("Share")

                DashboardChartIconSegmentedControl(selection: providerChartStyleBinding(for: data.provider))
            }

            if style == .bars {
                HStack(alignment: .center, spacing: 8) {
                    if let providerBarDateRangeLabel {
                        Text(providerBarDateRangeLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)

                    AppSegmentedControl(
                        selection: $barChartRange,
                        options: Array(BarChartRange.allCases),
                        title: { $0.title }
                    )
                    .fixedSize()
                }
                .transition(.opacity)
            } else if rowUsesExpandedViewport {
                HStack(alignment: .center, spacing: 8) {
                    Color.clear
                        .frame(height: 0)

                    Spacer(minLength: 0)

                    AppSegmentedControl(
                        selection: $barChartRange,
                        options: Array(BarChartRange.allCases),
                        title: { $0.title }
                    )
                    .fixedSize()
                    .hidden()
                }
            }

            /// If a row mixes Bars and Squares, let the Squares card inherit the taller viewport from its row mate.
            let chartViewportHeight = rowUsesExpandedViewport
                ? DashboardHeatmap.providerCardExpandedViewportHeight
                : DashboardHeatmap.providerCardHeatmapGridHeight
            Group {
                if style == .bars, data.total > 0 {
                    HStack(alignment: .center, spacing: 2) {
                        heatmapPanRail(
                            systemName: "chevron.backward",
                            disabled: providerOff >= providerMaxOff,
                            help: "Earlier days",
                            monthHeaderGutter: 0,
                            gridHeight: chartViewportHeight,
                            railSize: .compactStrip
                        ) {
                            providerHeatmapOffsets[data.provider] = min(
                                providerOff + ProviderCardHeatmap.panStepDays,
                                providerMaxOff
                            )
                        }

                        Chart(barStats) { stat in
                            BarMark(
                                x: .value("Day", stat.day, unit: .day),
                                y: .value("Count", stat.count)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .foregroundStyle(dashboardHighlight.opacity(0.75))
                        }
                        .frame(height: chartViewportHeight)
                        .frame(maxWidth: .infinity)
                        .chartXAxis {
                            barChartXAxis(range: barChartRange, labelFont: .caption2, gridOpacity: 0.1)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(.secondary.opacity(0.1))
                                AxisValueLabel()
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYScale(domain: 0...providerBarsMaxY)
                        .optionalChartXScale(providerBarsXDomain)
                        .allowsHitTesting(false)

                        heatmapPanRail(
                            systemName: "chevron.forward",
                            disabled: providerOff <= 0,
                            help: "Later days",
                            monthHeaderGutter: 0,
                            gridHeight: chartViewportHeight,
                            railSize: .compactStrip
                        ) {
                            providerHeatmapOffsets[data.provider] = max(
                                providerOff - ProviderCardHeatmap.panStepDays,
                                0
                            )
                        }
                    }
                } else {
                    DashboardHeatmap(
                        stats: heatmapStats,
                        accent: dashboardHighlight,
                        compact: true,
                        fillHorizontalSlack: true,
                        compactGridHeight: chartViewportHeight
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .compositingGroup()
            .animation(CodebookMotion.chartStyleSwap, value: style)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    hoveredMiniChartProvider == data.provider
                        ? Color(nsColor: .separatorColor).opacity(0.55)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(CodebookMotion.hover, value: hoveredMiniChartProvider)
        .onHover { hovering in
            hoveredMiniChartProvider = hovering ? data.provider : nil
        }
    }

    func providerChartStyleBinding(for provider: IntegrationProvider) -> Binding<DashboardChartStyle> {
        Binding(
            get: { providerDashboardChartStyles[provider, default: .heatmap] },
            set: { providerDashboardChartStyles[provider] = $0 }
        )
    }

    // MARK: - Share

    var sharePopoverContent: some View {
        let dashboardCostSummary = costSummary(for: model.importedPrompts)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Share Snapshot")
                .font(.headline)

            shareHeatmapGridView(stats: heatmapStats, maxContainerWidth: 308)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.importedPrompts.count) prompts across \(projectCount) projects")
                    .font(.caption.weight(.medium))
                if dashboardCostSummary.estimatedPromptCount > 0 {
                    Text("\(currencyString(dashboardCostSummary.amountUSD)) estimated cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if bestDayCount > 0 {
                    Text("Best day: \(bestDayCount) prompts on \(bestDayLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    copyDashboardShareCaption()
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                ShareLink(
                    item: dashboardShareCaption,
                    subject: Text("Codebook snapshot"),
                    message: Text("")
                ) {
                    Label("More...", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    func providerSharePopoverContent(data: ProviderMiniChartData) -> some View {
        let caption = providerDashboardShareCaption(data: data)
        let activeDays = data.historyStats.filter { $0.count > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            Text("Share \(data.provider.title)")
                .font(.headline)

            if data.total > 0 {
                shareHeatmapGridContent(stats: data.historyStats, maxContainerWidth: 288)
            } else {
                Text("No prompts for this source in this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(data.total) \(data.provider.title) prompts · last \(data.historyStats.count) days")
                    .font(.caption.weight(.medium))
                Text("Active \(activeDays) of \(data.historyStats.count) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(costLabel(for: data.prompts) + " \u{00B7} " + costCoverageLabel(for: data.prompts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    copyProviderShareCaption(data: data)
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                ShareLink(
                    item: caption,
                    subject: Text("Codebook · \(data.provider.title)"),
                    message: Text("")
                ) {
                    Label("More...", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    func copyProviderShareCaption(data: ProviderMiniChartData) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(providerDashboardShareCaption(data: data), forType: .string)
        copiedProviderShare = data.provider
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if copiedProviderShare == data.provider {
                    copiedProviderShare = nil
                }
            }
        }
    }

    func providerDashboardShareCaption(data: ProviderMiniChartData) -> String {
        let grid = emojiHeatmapClipboardGrid(stats: data.historyStats)
        let activeDays = data.historyStats.filter { $0.count > 0 }.count
        var caption = ""
        if !grid.isEmpty {
            caption += grid + "\n\n"
        }
        caption += "\(data.total) \(data.provider.title) prompts (last \(data.historyStats.count) days)\n"
        caption += "Active \(activeDays) of \(data.historyStats.count) days\n"
        if data.estimatedCostSummary.estimatedPromptCount > 0 {
            caption += "\(currencyString(data.estimatedCostSummary.amountUSD)) estimated cost \u{00B7} \(costCoverageLabel(for: data.prompts))\n"
        }
        caption += "from Codebook"
        return caption
    }

    /// SwiftUI colored rectangle grid for the share popover (pixel-perfect alignment).
    func shareHeatmapGridView(stats: [DailyPromptStat], maxContainerWidth: CGFloat = 310) -> some View {
        Group {
            if stats.isEmpty {
                Color.clear.frame(height: 1)
            } else {
                shareHeatmapGridContent(stats: stats, maxContainerWidth: maxContainerWidth)
            }
        }
    }

    func shareHeatmapGridContent(stats: [DailyPromptStat], maxContainerWidth: CGFloat) -> some View {
        let calendar = Calendar.current
        let maxCount = max(stats.map(\.count).max() ?? 1, 1)
        let ordered = stats.sorted { $0.day < $1.day }

        let cells: [DailyPromptStat?] = {
            guard let firstDay = ordered.first?.day else { return [] }
            let leadPad = (calendar.component(.weekday, from: firstDay) + 5) % 7
            var c: [DailyPromptStat?] = Array(repeating: nil, count: leadPad)
            c.append(contentsOf: ordered.map(Optional.some))
            while c.count % 7 != 0 { c.append(nil) }
            return c
        }()

        let numWeeks = max(cells.count / 7, 1)
        /// Fixed geometry so every cell matches; scroll horizontally if the window is narrower than the grid.
        let cellSide: CGFloat = 10
        let cellGap: CGFloat = 2
        let gridWidth = CGFloat(numWeeks) * cellSide + CGFloat(max(0, numWeeks - 1)) * cellGap

        let grid = HStack(alignment: .top, spacing: cellGap) {
            ForEach(0..<numWeeks, id: \.self) { week in
                VStack(spacing: cellGap) {
                    ForEach(0..<7, id: \.self) { row in
                        let index = week * 7 + row
                        let stat = index < cells.count ? cells[index] : nil
                        RoundedRectangle(cornerRadius: max(cellSide * 0.18, 1.5))
                            .fill(shareSquareColor(stat: stat, maxCount: maxCount))
                            .frame(width: cellSide, height: cellSide)
                    }
                }
            }
        }

        return Group {
            if gridWidth > maxContainerWidth {
                ScrollView(.horizontal, showsIndicators: false) {
                    grid
                }
                .frame(maxWidth: maxContainerWidth)
            } else {
                grid
            }
        }
    }

    func shareSquareColor(stat: DailyPromptStat?, maxCount: Int) -> Color {
        guard let stat, stat.count > 0 else {
            return stat == nil ? Color.secondary.opacity(0.04) : Color.secondary.opacity(0.1)
        }
        let ratio = Double(stat.count) / Double(maxCount)
        if ratio < 0.26 { return dashboardHighlight.opacity(0.3) }
        if ratio < 0.51 { return dashboardHighlight.opacity(0.5) }
        if ratio < 0.76 { return dashboardHighlight.opacity(0.72) }
        return dashboardHighlight
    }

    /// Emoji grid for clipboard: one square emoji per cell — ramp **⬜ → 🟦 → 🟪 → ⬛** (white / blue / purple / black).
    var emojiHeatmapClipboardGrid: String {
        emojiHeatmapClipboardGrid(stats: heatmapStats)
    }

    func emojiHeatmapClipboardGrid(stats: [DailyPromptStat]) -> String {
        let clippedStats = clippedClipboardHeatmapStats(stats)
        guard !clippedStats.isEmpty else { return "" }
        let calendar = Calendar.current
        let maxCount = max(clippedStats.map(\.count).max() ?? 1, 1)

        let ordered = clippedStats.sorted { $0.day < $1.day }
        let firstDay = ordered[0].day
        let firstWeekday = (calendar.component(.weekday, from: firstDay) + 5) % 7

        var cells: [DailyPromptStat?] = Array(repeating: nil, count: firstWeekday)
        cells.append(contentsOf: ordered.map(Optional.some))
        while cells.count % 7 != 0 { cells.append(nil) }

        let numWeeks = cells.count / 7
        var lines: [String] = []

        for row in 0..<7 {
            var line = ""
            for week in 0..<numWeeks {
                let index = week * 7 + row
                if index < cells.count, let stat = cells[index] {
                    line += shareHeatmapEmojiCell(count: stat.count, maxCount: maxCount)
                } else {
                    line += "\u{2B1C}" // ⬜ white — inactive / padding
                }
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    func shareHeatmapEmojiCell(count: Int, maxCount: Int) -> String {
        guard count > 0 else { return "\u{2B1C}" } // ⬜ white — tracked day, zero prompts
        let ratio = Double(count) / Double(maxCount)
        if ratio < 0.26 { return "\u{1F7E6}" } // 🟦 blue — first intensity band (matches share square ramp)
        if ratio < 0.76 { return "\u{1F7EA}" } // 🟪 purple — through upper-mid band
        return "\u{2B1B}" // ⬛ black — top band
    }

    var dashboardShareCaption: String {
        let grid = emojiHeatmapClipboardGrid
        let total = model.importedPrompts.count
        let projects = projectCount
        let activeDays = activeHeatmapDays
        let totalDays = heatmapStats.count
        let estimatedCost = costSummary(for: model.importedPrompts)

        var caption = ""
        if !grid.isEmpty {
            caption += grid + "\n\n"
        }
        caption += "\(total) prompts across \(projects) projects\n"
        caption += "Active \(activeDays) of \(totalDays) days\n"
        if estimatedCost.estimatedPromptCount > 0 {
            caption += "\(currencyString(estimatedCost.amountUSD)) estimated cost\n"
        }
        caption += "from Codebook"

        return caption
    }

    func clippedClipboardHeatmapStats(_ stats: [DailyPromptStat]) -> [DailyPromptStat] {
        let maxDays = ClipboardHeatmapShare.maxWeeks * 7
        guard stats.count > maxDays else { return stats }
        return Array(stats.suffix(maxDays))
    }

    func copyDashboardShareCaption() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(dashboardShareCaption, forType: .string)
        copiedShareCaption = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedShareCaption = false
        }
    }

    // MARK: - Batch Send

    /// Reusable button for batch-copying prompts to clipboard.
    func batchSendMenu(label: String, scope: BatchScope, prompts: [ImportedPrompt]? = nil) -> some View {
        Button {
            copyBatchPrompts(scope: scope, prompts: prompts)
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    func copyBatchPrompts(scope: BatchScope, prompts explicitPrompts: [ImportedPrompt]? = nil) {
        let prompts: [ImportedPrompt]
        if let explicitPrompts {
            prompts = explicitPrompts
        } else {
            switch scope {
            case .commit(let sha):
                prompts = model.importedPrompts.filter { $0.commitSHA == sha }
            case .day(let key):
                let group = model.dayGroups.first(where: { $0.id == "day-\(key)" })
                prompts = group?.groups.flatMap(\.prompts) ?? []
            case .thread(let key):
                let group = model.dayGroups
                    .flatMap(\.groups)
                    .first(where: { $0.id == key })
                prompts = group?.prompts ?? []
            case .repo:
                prompts = model.visiblePrompts
            }
        }
        let text = prompts.map(\.body).joined(separator: "\n\n---\n\n")
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Helpers

    func timeString(_ date: Date) -> String {
        ViewFormatters.shortTime.string(from: date)
    }

    func confidenceColor(_ confidence: CommitConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }

    func copyPrompt(_ prompt: ImportedPrompt) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt.body, forType: .string)
        copiedPromptID = prompt.id
    }

    func costSummary(for prompts: [ImportedPrompt]) -> PromptCostSummary {
        PromptCostEstimator.summarize(prompts)
    }

    func responseTimeSummary(for prompts: [ImportedPrompt]) -> PromptTimingSummary {
        PromptTimingEstimator.summarize(prompts)
    }

    func costLabel(for prompts: [ImportedPrompt]) -> String {
        let summary = costSummary(for: prompts)
        guard summary.estimatedPromptCount > 0, summary.coverageRatio >= 1.0 else { return "" }
        return currencyString(summary.amountUSD)
    }

    func costCoverageLabel(for prompts: [ImportedPrompt]) -> String {
        let summary = costSummary(for: prompts)
        guard summary.totalPromptCount > 0 else { return "0% coverage" }
        return "\(Int((summary.coverageRatio * 100).rounded()))% coverage"
    }

    func responseTimeLabel(for prompts: [ImportedPrompt]) -> String {
        let summary = responseTimeSummary(for: prompts)
        guard summary.measuredPromptCount > 0, summary.coverageRatio >= 1.0 else { return "" }
        return formatDuration(milliseconds: summary.totalResponseTimeMs)
    }

    func currencyString(_ amount: Double) -> String {
        let formatter = amount >= 1 ? ViewFormatters.usdCurrency2 : ViewFormatters.usdCurrency4
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.4f", amount)
    }

    func formatTokenCount(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    func formatDuration(milliseconds: Int) -> String {
        let totalSeconds = Double(milliseconds) / 1000.0
        if totalSeconds < 1 {
            return "\(milliseconds)ms"
        }
        if totalSeconds < 10 {
            return String(format: "%.1fs", totalSeconds)
        }

        let roundedSeconds = Int(totalSeconds.rounded())
        if roundedSeconds < 60 {
            return "\(roundedSeconds)s"
        }

        let minutes = roundedSeconds / 60
        let seconds = roundedSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    /// Total tokens for display: reported total when present, otherwise input + output (or lone side) when measurable.
    func importMetadataTokenDisplayTotal(for prompt: ImportedPrompt) -> Int? {
        guard prompt.hasMeasuredUsage else { return nil }
        if let total = prompt.totalTokens { return total }
        switch (prompt.inputTokens, prompt.outputTokens) {
        case let (i?, o?): return i + o
        case let (i?, nil): return i
        case let (nil, o?): return o
        default: return nil
        }
    }

    @ViewBuilder
    func importMetadataPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Dashboard Data

    func rebuildDashboardDerivedData() {
        dashboardDerivedData = Self.buildDashboardDerivedData(
            prompts: model.importedPrompts,
            projectCount: model.projectSummaries.filter { $0.id != "all-projects" }.count
        )
        clampHeatmapWindowOffset()
        clampBarChartWindowOffset()
        clampProviderHeatmapOffsets()
    }

    static func buildDashboardDerivedData(
        prompts: [ImportedPrompt],
        projectCount: Int
    ) -> DashboardDerivedData {
        let calendar = Calendar.current
        let heatmapEnd = calendar.startOfDay(for: Date())
        let heatmapDays = ActivityHeatmapPan.historyDayCount
        let heatmapStart = calendar.date(byAdding: .day, value: -(heatmapDays - 1), to: heatmapEnd) ?? heatmapEnd
        let promptsByDay = Dictionary(grouping: prompts) { prompt in
            calendar.startOfDay(for: prompt.commitDate ?? prompt.capturedAt)
        }

        let heatmapStats = stride(from: 0, to: heatmapDays, by: 1).compactMap { offset -> DailyPromptStat? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: heatmapStart) else { return nil }
            let promptsForDay = promptsByDay[day] ?? []
            let commitsBySHA = promptsForDay.reduce(into: [String: DailyCommitStat]()) { result, prompt in
                guard let sha = prompt.commitSHA else { return }
                result[sha] = result[sha] ?? DailyCommitStat(sha: sha, message: prompt.commitMessage)
            }
            let commits = Array(commitsBySHA.values).sorted { lhs, rhs in
                if lhs.message == rhs.message {
                    return lhs.sha < rhs.sha
                }
                return (lhs.message ?? "") < (rhs.message ?? "")
            }

            return DailyPromptStat(
                id: day,
                day: day,
                count: promptsForDay.count,
                commits: commits
            )
        }

        let providerPrompts = Dictionary(grouping: prompts, by: \.provider)
        let providerStats = IntegrationProvider.allCases.compactMap { provider -> ProviderStat? in
            let count = providerPrompts[provider]?.count ?? 0
            return count == 0 ? nil : ProviderStat(id: provider.rawValue, name: provider.title, count: count)
        }
        .sorted { $0.count > $1.count }

        let providerHeatmapEnd = calendar.startOfDay(for: Date())
        let providerHeatmapDays = ProviderCardHeatmap.historyDayCount
        let providerHeatmapStart = calendar.date(byAdding: .day, value: -(providerHeatmapDays - 1), to: providerHeatmapEnd) ?? providerHeatmapEnd
        let providerMiniCharts = IntegrationProvider.allCases.map { provider in
            let promptsForProvider = providerPrompts[provider] ?? []
            let byDay = Dictionary(grouping: promptsForProvider) { prompt in
                calendar.startOfDay(for: prompt.commitDate ?? prompt.capturedAt)
            }
            let historyStats = stride(from: 0, to: providerHeatmapDays, by: 1).compactMap { offset -> DailyPromptStat? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: providerHeatmapStart) else { return nil }
                return DailyPromptStat(id: day, day: day, count: byDay[day]?.count ?? 0, commits: [])
            }
            return ProviderMiniChartData(
                provider: provider,
                total: promptsForProvider.count,
                prompts: promptsForProvider,
                estimatedCostSummary: PromptCostEstimator.summarize(promptsForProvider),
                historyStats: historyStats
            )
        }

        let structuredPromptCount = prompts.reduce(into: 0) { count, prompt in
            if prompt.commitSHA != nil {
                count += 1
            }
        }
        let structuredPromptRate: Int = {
            guard !prompts.isEmpty else { return 0 }
            return Int((Double(structuredPromptCount) / Double(prompts.count) * 100).rounded())
        }()

        let activeDaySet = Set(heatmapStats.lazy.filter { $0.count > 0 }.map { calendar.startOfDay(for: $0.day) })
        let activeHeatmapDays = activeDaySet.count

        var currentStreak = 0
        var checkDay = heatmapEnd
        if !activeDaySet.contains(checkDay) {
            checkDay = calendar.date(byAdding: .day, value: -1, to: checkDay) ?? checkDay
        }
        while activeDaySet.contains(checkDay) {
            currentStreak += 1
            checkDay = calendar.date(byAdding: .day, value: -1, to: checkDay) ?? checkDay
        }

        let bestDayStat = heatmapStats.max { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.day < rhs.day
            }
            return lhs.count < rhs.count
        }
        let bestDayLabel = bestDayStat.map {
            $0.day.formatted(.dateTime.month(.abbreviated).day())
        } ?? "no data yet"

        return DashboardDerivedData(
            heatmapStats: heatmapStats,
            structuredPromptCount: structuredPromptCount,
            structuredPromptRate: structuredPromptRate,
            projectCount: projectCount,
            providerStats: providerStats,
            providerMiniCharts: providerMiniCharts,
            activeHeatmapDays: activeHeatmapDays,
            currentStreak: currentStreak,
            bestDayStat: bestDayStat,
            bestDayLabel: bestDayLabel
        )
    }

    var heatmapStats: [DailyPromptStat] {
        dashboardDerivedData.heatmapStats
    }

    var barStats: [DailyPromptStat] {
        let full = heatmapStats
        let n = barChartRange.days
        guard !full.isEmpty, n > 0 else { return [] }
        let lastIdx = full.count - 1
        let windowEndIdx = lastIdx - barChartWindowEndOffset
        guard windowEndIdx >= 0, windowEndIdx < full.count else {
            return Array(full.suffix(min(n, full.count)))
        }
        let windowStartIdx = windowEndIdx - n + 1
        let s = max(0, windowStartIdx)
        let e = min(windowEndIdx, full.count - 1)
        guard s <= e else { return [] }
        return Array(full[s...e])
    }

    var maxBarChartWindowOffset: Int {
        let full = heatmapStats
        let n = barChartRange.days
        guard !full.isEmpty, n > 0 else { return 0 }
        return max(0, full.count - n)
    }

    func clampBarChartWindowOffset() {
        barChartWindowEndOffset = min(barChartWindowEndOffset, maxBarChartWindowOffset)
    }

    /// Fixed ~182-day viewport into `heatmapStats` (pan does not follow bar-chart range).
    var heatmapVisibleStats: [DailyPromptStat] {
        let full = heatmapStats
        let n = ActivityHeatmapPan.viewportDayCount
        guard !full.isEmpty, n > 0 else { return [] }
        let lastIdx = full.count - 1
        let windowEndIdx = lastIdx - heatmapWindowEndOffset
        guard windowEndIdx >= 0, windowEndIdx < full.count else {
            return Array(full.suffix(min(n, full.count)))
        }
        let windowStartIdx = windowEndIdx - n + 1
        let s = max(0, windowStartIdx)
        let e = min(windowEndIdx, full.count - 1)
        guard s <= e else { return [] }
        return Array(full[s...e])
    }

    var maxHeatmapWindowOffset: Int {
        let full = heatmapStats
        let n = ActivityHeatmapPan.viewportDayCount
        guard !full.isEmpty, n > 0 else { return 0 }
        return max(0, full.count - n)
    }

    func clampHeatmapWindowOffset() {
        heatmapWindowEndOffset = min(heatmapWindowEndOffset, maxHeatmapWindowOffset)
    }

    func heatmapWindowRangeLabel(from first: Date, to last: Date) -> String {
        let cal = Calendar.current
        let y1 = cal.component(.year, from: first)
        let y2 = cal.component(.year, from: last)
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = last.formatted(
            y1 == y2
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
        )
        return "\(start)–\(end)"
    }

    var structuredPromptCount: Int {
        dashboardDerivedData.structuredPromptCount
    }

    var structuredPromptRate: Int {
        dashboardDerivedData.structuredPromptRate
    }

    var projectCount: Int {
        dashboardDerivedData.projectCount
    }

    var providerStats: [ProviderStat] {
        dashboardDerivedData.providerStats
    }

    var dashboardMetrics: [DashboardMetric] {
        let total = model.importedPrompts.count
        let activeDays = activeHeatmapDays
        let avgPerDay: String = {
            guard activeDays > 0 else { return "0" }
            let avg = Double(total) / Double(activeDays)
            return avg >= 10 ? "\(Int(avg.rounded()))" : String(format: "%.1f", avg)
        }()
        let streak = currentStreak

        return [
            DashboardMetric(
                id: "prompts",
                title: "Total Prompts",
                value: "\(total)",
                trailingValue: nil,
                subtitle: nil
            ),
            DashboardMetric(
                id: "active-days",
                title: "Active Days",
                value: "\(activeDays)",
                trailingValue: "/\(heatmapStats.count)",
                subtitle: nil
            ),
            DashboardMetric(
                id: "avg-per-day",
                title: "Avg / Active Day",
                value: avgPerDay,
                trailingValue: "/day",
                subtitle: nil
            ),
            DashboardMetric(
                id: "streak",
                title: "Current Streak",
                value: "\(streak)",
                trailingValue: streak == 1 ? " day" : " days",
                subtitle: nil
            )
        ]
    }

    var currentStreak: Int {
        dashboardDerivedData.currentStreak
    }

    var activeHeatmapDays: Int {
        dashboardDerivedData.activeHeatmapDays
    }

    var bestDayStat: DailyPromptStat? {
        dashboardDerivedData.bestDayStat
    }

    var bestDayCount: Int {
        bestDayStat?.count ?? 0
    }

    var bestDayLabel: String {
        dashboardDerivedData.bestDayLabel
    }

    var dashboardHighlight: Color {
        .accentColor
    }

    var dashboardAccent: Color {
        Color.accentColor.opacity(0.7)
    }
}

struct PromptStoreConfirmationRequest: Identifiable {
    enum Action: Equatable {
        case createFolder
        case turnOn
        case deleteFolder

        var buttonTitle: String {
            switch self {
            case .createFolder:
                return "Create prompts/"
            case .turnOn:
                return "Turn On"
            case .deleteFolder:
                return "Delete prompts/"
            }
        }
    }

    let id = UUID()
    let project: ProjectSummary
    let action: Action
}

struct PromptStoreConfirmationSheet: View {
    let request: PromptStoreConfirmationRequest
    let confirm: () -> Void
    let cancel: () -> Void

    var primaryMessage: String {
        switch request.action {
        case .createFolder, .turnOn:
            return "This creates `prompts/` in the repository."
        case .deleteFolder:
            return "This deletes `prompts/` and turns off automatic prompt syncing for this repository."
        }
    }

    var secondaryMessage: String {
        switch request.action {
        case .createFolder:
            return "You can turn on syncing after the folder is created."
        case .turnOn:
            return "Automatic prompt syncing will also be turned on."
        case .deleteFolder:
            return "Use this if you want to return to the install screen and start fresh."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.action.buttonTitle)
                .font(.title3.weight(.semibold))

            Text(request.project.name)
                .font(.headline)

            if let path = request.project.path {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(primaryMessage)
                Text(secondaryMessage)
                Text("Use Cancel if this is not the right repository.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                if request.action == .deleteFolder {
                    Button(request.action.buttonTitle, role: .destructive, action: confirm)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(request.action.buttonTitle, action: confirm)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
