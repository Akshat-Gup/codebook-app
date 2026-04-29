import Charts
import SwiftUI

// MARK: - Heatmap (Full-Width)

struct DashboardHeatmap: View {
    let stats: [DailyPromptStat]
    let accent: Color
    /// Smaller grid without month row or legend (provider sub-cards on the dashboard).
    var compact: Bool = false
    /// Widen inter-week gaps to fill width (hero). Off for mini-cards so columns stay tight.
    var fillHorizontalSlack: Bool
    /// When set, overrides `compactGridHeight` so Squares on provider cards can use a taller viewport.
    var compactGridHeight: CGFloat?
    /// When set, overrides the non-compact grid height (default 248).
    var gridHeight: CGFloat?
    /// Maximum square side length — raise for grids with fewer weeks so cells fill the space.
    var maxSquareSize: CGFloat

    init(
        stats: [DailyPromptStat],
        accent: Color,
        compact: Bool = false,
        fillHorizontalSlack: Bool? = nil,
        compactGridHeight: CGFloat? = nil,
        gridHeight: CGFloat? = nil,
        maxSquareSize: CGFloat = 34
    ) {
        self.stats = stats
        self.accent = accent
        self.compact = compact
        self.fillHorizontalSlack = fillHorizontalSlack ?? !compact
        self.compactGridHeight = compactGridHeight
        self.gridHeight = gridHeight
        self.maxSquareSize = maxSquareSize
    }

    /// Grid height for `compact` mode (rails + `ContentView` must stay in sync).
    static let compactGridHeight: CGFloat = 76

    /// Taller `compact` grid for provider dashboard Squares (full `ProviderCardHeatmap` history).
    static let providerCardHeatmapGridHeight: CGFloat = 172
    static let providerCardExpandedViewportHeight: CGFloat = providerCardHeatmapGridHeight + 34

    /// Non-compact hero: month row + inner spacing + grid + spacing + legend row — keep in sync with `body`.
    static let heroLayoutTotalHeight: CGFloat = 20 + 10 + 248 + 10 + 24

    static func fittedWidth(
        for stats: [DailyPromptStat],
        gridHeight: CGFloat,
        maxSquareSize: CGFloat
    ) -> CGFloat {
        guard !stats.isEmpty else { return 0 }

        let calendar = Calendar.current
        let ordered = stats.sorted { $0.day < $1.day }
        let firstWeekday = calendar.component(.weekday, from: ordered[0].day)
        let leadingPadding = (firstWeekday + 5) % 7
        let cellCount = leadingPadding + ordered.count
        let weekCount = max(Int(ceil(Double(cellCount) / 7.0)), 1)
        let spacing: CGFloat = 3
        let maxSquareByHeight = (gridHeight - 6 * spacing) / 7
        let squareSize = max(min(maxSquareByHeight, maxSquareSize), 6)

        return CGFloat(weekCount) * squareSize + CGFloat(max(weekCount - 1, 0)) * spacing
    }

    @State private var hoveredStatID: TimeInterval?
    @State private var hoveredTooltipPosition: CGPoint?

    private var calendar: Calendar { .current }

    private var maxCount: Int {
        max(stats.map(\.count).max() ?? 0, 1)
    }

    private var weeks: [[DailyPromptStat?]] {
        guard !stats.isEmpty else { return [] }
        let ordered = stats.sorted { $0.day < $1.day }
        let firstDay = ordered[0].day
        let leadingPadding = weekdayIndex(firstDay)
        var cells: [DailyPromptStat?] = Array(repeating: nil, count: leadingPadding)
        cells.append(contentsOf: ordered.map(Optional.some))
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map { index in
            Array(cells[index ..< min(index + 7, cells.count)])
        }
    }

    private var monthLabels: [String?] {
        weeks.enumerated().map { index, week in
            guard let firstStat = week.compactMap({ $0 }).first else { return nil }
            let month = calendar.component(.month, from: firstStat.day)
            if index == 0 { return monthLabel(for: firstStat.day) }

            let priorMonth = weeks[index - 1]
                .compactMap { $0 }
                .first
                .map { calendar.component(.month, from: $0.day) }

            return priorMonth == month ? nil : monthLabel(for: firstStat.day)
        }
    }

    /// Row height for month labels (must match `ContentView.ActivityHeatmapPan.monthHeaderGutter`).
    private var heatmapMonthHeaderRowHeight: CGFloat { 20 }

    /// `gridSpacing` is used for **both** week↔week and day↔day gaps so gutters stay square when filling width.
    private func weekStripMetrics(width: CGFloat, gridHeight: CGFloat, fillHorizontalSlack: Bool) -> (squareSize: CGFloat, gridSpacing: CGFloat) {
        let weekCount = CGFloat(max(weeks.count, 1))
        let gridSpacing: CGFloat = 3
        let maxSquareByHeight = (gridHeight - 6 * gridSpacing) / 7
        let maxSquareByWidth = (width - (weekCount - 1) * gridSpacing) / weekCount
        var squareSize = max(min(min(maxSquareByWidth, maxSquareByHeight), maxSquareSize), 6)

        if fillHorizontalSlack {
            let heightCap = min(maxSquareByHeight, maxSquareSize)
            var slack = width - (weekCount * squareSize + (weekCount - 1) * gridSpacing)
            if slack > 0 {
                squareSize = min(squareSize + slack / weekCount, heightCap)
                slack = width - (weekCount * squareSize + (weekCount - 1) * gridSpacing)
                if slack > 0 {
                    squareSize = min(squareSize + slack / weekCount, heightCap)
                }
            }
        }

        return (squareSize, gridSpacing)
    }

    @ViewBuilder
    private func weekGridContent(proxyWidth: CGFloat, proxyHeight: CGFloat) -> some View {
        let metrics = weekStripMetrics(width: proxyWidth, gridHeight: proxyHeight, fillHorizontalSlack: fillHorizontalSlack)
        let squareSize = metrics.squareSize
        let g = metrics.gridSpacing
        let hoveredTooltipStat = stats.first(where: { $0.day.timeIntervalSince1970 == hoveredStatID })

        HStack(alignment: .top, spacing: g) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                VStack(spacing: g) {
                    ForEach(Array(week.enumerated()), id: \.offset) { rowIndex, stat in
                        let x = CGFloat(weekIndex) * (squareSize + g) + (squareSize / 2)
                        let y = CGFloat(rowIndex) * (squareSize + g)
                        let statID = stat?.day.timeIntervalSince1970
                        let isHovered = statID != nil && hoveredStatID == statID
                        RoundedRectangle(cornerRadius: max(squareSize * 0.2, 2))
                            .fill(fillColor(for: stat))
                            .frame(width: squareSize, height: squareSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: max(squareSize * 0.2, 2))
                                    .strokeBorder(
                                        isHovered ? Color.white.opacity(0.55) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .onHover { hovering in
                                if hovering, statID != nil {
                                    hoveredStatID = statID
                                    hoveredTooltipPosition = CGPoint(x: x, y: y)
                                } else if hoveredStatID == statID {
                                    hoveredStatID = nil
                                    hoveredTooltipPosition = nil
                                }
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay {
            if let hoveredStat = hoveredTooltipStat, let hoveredTooltipPosition {
                heatmapTooltip(for: hoveredStat)
                    .position(
                        x: min(max(hoveredTooltipPosition.x, 96), max(proxyWidth - 96, 96)),
                        y: max(hoveredTooltipPosition.y - 18, 12)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if compact {
                GeometryReader { proxy in
                    weekGridContent(proxyWidth: proxy.size.width, proxyHeight: proxy.size.height)
                }
                .frame(height: compactGridHeight ?? Self.compactGridHeight)
            } else {
                GeometryReader { proxy in
                    let gridH = heatmapGridHeight
                    let m = weekStripMetrics(width: proxy.size.width, gridHeight: gridH, fillHorizontalSlack: fillHorizontalSlack)
                    VStack(alignment: .center, spacing: 10) {
                        HStack(spacing: m.gridSpacing) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { idx, _ in
                                let lab = idx < monthLabels.count ? monthLabels[idx] : nil
                                Text(lab ?? "")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: m.squareSize, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.65)
                            }
                        }
                        .frame(height: heatmapMonthHeaderRowHeight)

                        weekGridContent(proxyWidth: proxy.size.width, proxyHeight: gridH)
                            .frame(height: gridH, alignment: .center)
                    }
                    .frame(width: proxy.size.width)
                }
                .frame(height: heatmapMonthHeaderRowHeight + 10 + heatmapGridHeight)
                .clipped()
            }

            if !compact {
                HStack(spacing: 6) {
                    Text("Less")
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(legendColor(level: index))
                            .frame(width: 12, height: 12)
                    }
                    Text("More")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heatmapGridHeight: CGFloat {
        gridHeight ?? 248
    }

    private func weekdayIndex(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private func fillColor(for stat: DailyPromptStat?) -> Color {
        guard let stat, stat.count > 0 else {
            if compact {
                return Color.primary.opacity(stat == nil ? 0.06 : 0.14)
            }
            return Color.secondary.opacity(stat == nil ? 0.04 : 0.1)
        }

        let ratio = Double(stat.count) / Double(maxCount)
        switch ratio {
        case 0..<0.26:
            return accent.opacity(0.3)
        case 0.26..<0.51:
            return accent.opacity(0.5)
        case 0.51..<0.76:
            return accent.opacity(0.72)
        default:
            return accent
        }
    }

    private func legendColor(level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.1)
        case 1: return accent.opacity(0.3)
        case 2: return accent.opacity(0.5)
        case 3: return accent
        default: return accent
        }
    }

    private func heatmapTooltip(for stat: DailyPromptStat) -> some View {
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
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func monthLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }
}

extension View {
    /// Pins the temporal X scale to the visible slice so bars span the plot width instead of floating with default insets.
    @ViewBuilder
    func optionalChartXScale(_ domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain)
        } else {
            self
        }
    }
}
