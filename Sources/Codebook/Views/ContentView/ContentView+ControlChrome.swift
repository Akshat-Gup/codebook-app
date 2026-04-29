import SwiftUI

// MARK: - Shared control chrome (dashboard, filters, settings, automations)

enum AppControlChrome {
    /// Neutral fill for secondary buttons and segmented tracks — adapts across light/dark.
    static let softSurface = Color(nsColor: .controlColor)
    /// Active segment / primary filled control (~#3B82F6).
    static let segmentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    /// Label on control surfaces — adapts across light/dark.
    static let charcoal = Color(nsColor: .labelColor)

    /// Frosted glass for dashboard share actions; matches `SegmentedControlTrackStyle.materials` pill treatment.
    /// `Material` is only applied where the SDK supports it (macOS 11+); this app targets macOS 15+.
    @ViewBuilder
    static func glassShareButtonBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 11.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(softSurface)
        }
    }
}

enum SegmentedControlTrackStyle {
    /// Flat `NSColor` fills (opt-in if materials ever feel heavy somewhere).
    case solid
    /// Frosted track + raised glassy pill (default across pickers).
    case materials
}

/// Sliding-pill segmented control: no `Button`, fixed width, equal columns — materials optional.
struct SidebarStyleSegmentedControl<Option: Hashable, Label: View>: View {
    @Binding var selection: Option
    let options: [Option]
    var trackPadding: CGFloat = 2
    var segmentMinHeight: CGFloat = 26
    var pillAnimation: Animation = .easeOut(duration: 0.12)
    /// When set, used for both taps and the sliding pill (e.g. dashboard Bars ↔ Squares spring).
    var selectionAnimation: Animation?
    /// Sum of segment widths before outer track padding (drives minimum total width).
    var minSegmentWidth: CGFloat = 34
    var trackStyle: SegmentedControlTrackStyle = .materials
    var optionHelp: ((Option) -> String?)?

    @ViewBuilder private let label: (Option, Bool) -> Label

    private var resolvedSelectionAnimation: Animation {
        selectionAnimation ?? pillAnimation
    }

    init(
        selection: Binding<Option>,
        options: [Option],
        trackPadding: CGFloat = 2,
        segmentMinHeight: CGFloat = 26,
        pillAnimation: Animation = .easeOut(duration: 0.12),
        selectionAnimation: Animation? = nil,
        minSegmentWidth: CGFloat = 34,
        trackStyle: SegmentedControlTrackStyle = .materials,
        optionHelp: ((Option) -> String?)? = nil,
        @ViewBuilder label: @escaping (Option, Bool) -> Label
    ) {
        _selection = selection
        self.options = options
        self.trackPadding = trackPadding
        self.segmentMinHeight = segmentMinHeight
        self.pillAnimation = pillAnimation
        self.selectionAnimation = selectionAnimation
        self.minSegmentWidth = minSegmentWidth
        self.trackStyle = trackStyle
        self.optionHelp = optionHelp
        self.label = label
    }

    private var optionCount: Int {
        max(options.count, 1)
    }

    private var selectedIndex: Int {
        let idx = options.firstIndex(of: selection) ?? 0
        return min(max(idx, 0), max(options.count - 1, 0))
    }

    private var trackFill: AnyShapeStyle {
        switch trackStyle {
        case .solid:
            AnyShapeStyle(Color(nsColor: .controlColor))
        case .materials:
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var pillFill: AnyShapeStyle {
        switch trackStyle {
        case .solid:
            AnyShapeStyle(Color(nsColor: .textBackgroundColor))
        case .materials:
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var pillStroke: Color {
        switch trackStyle {
        case .solid:
            Color(nsColor: .separatorColor).opacity(0.4)
        case .materials:
            Color.white.opacity(0.18)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let innerW = max(geo.size.width - trackPadding * 2, 0)
            let innerH = max(geo.size.height - trackPadding * 2, 0)
            let segW = innerW / CGFloat(optionCount)
            let idx = selectedIndex
            let pillInset: CGFloat = 1

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(trackFill)

                Group {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(pillFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(pillStroke, lineWidth: 0.5)
                        )
                        .shadow(
                            color: trackStyle == .materials ? Color.black.opacity(0.12) : .clear,
                            radius: trackStyle == .materials ? 2 : 0,
                            y: trackStyle == .materials ? 1 : 0
                        )
                }
                .frame(width: max(segW - pillInset * 2, 0), height: max(innerH - pillInset * 2, 0))
                .offset(x: trackPadding + pillInset + CGFloat(idx) * segW, y: trackPadding + pillInset)
                .animation(resolvedSelectionAnimation, value: idx)

                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        segmentLayer(option: option, segmentWidth: segW, innerHeight: innerH)
                    }
                }
                .offset(x: trackPadding, y: trackPadding)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 0.5)
            )
            .compositingGroup()
        }
        // Fixed width: `GeometryReader` + `minWidth` was absorbing all remaining HStack space and stretching segments.
        .frame(width: CGFloat(optionCount) * minSegmentWidth + trackPadding * 2)
        .frame(height: segmentMinHeight + trackPadding * 2)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func segmentLayer(option: Option, segmentWidth: CGFloat, innerHeight: CGFloat) -> some View {
        let isSelected = selection == option
        let help = optionHelp?(option) ?? ""
        label(option, isSelected)
            .frame(width: segmentWidth, height: innerHeight, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture {
                guard selection != option else { return }
                withAnimation(resolvedSelectionAnimation) {
                    selection = option
                }
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .modifier(OptionalAccessibilityHint(hint: help.isEmpty ? nil : help))
    }
}

/// Uses `.accessibilityHint` instead of `.help` so tooltip tracking doesn't alter hover layout.
struct OptionalAccessibilityHint: ViewModifier {
    var hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

struct AppSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        SidebarStyleSegmentedControl(
            selection: $selection,
            options: options,
            minSegmentWidth: 42,
            optionHelp: nil
        ) { option, isSelected in
            Text(title(option))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
        }
    }
}

struct ProviderSourceToggleRow: View {
    let provider: IntegrationProvider
    let isOn: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PlatformIconView(provider: provider, size: 18)
                Text(provider.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppControlChrome.charcoal)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(isOn ? "On" : "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : AppControlChrome.charcoal.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOn ? AppControlChrome.segmentBlue : AppControlChrome.softSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(isOn ? 0 : 0.18), lineWidth: 0.5)
                    )
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

enum DashboardChartStyle: String, CaseIterable {
    case bars
    case heatmap

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .heatmap: return "Squares"
        }
    }

    /// Compact toolbar / provider cards (hero still uses `title`).
    var systemImage: String {
        switch self {
        case .bars: return "chart.bar.fill"
        case .heatmap: return "square.grid.3x3.fill"
        }
    }
}

/// Hero Activity row: frosted track + raised pill (original look); interaction stays SwiftUI tap targets.
struct DashboardHeroChartStyleControl: View {
    @Binding var selection: DashboardChartStyle

    var body: some View {
        SidebarStyleSegmentedControl(
            selection: $selection,
            options: DashboardChartStyle.allCases,
            selectionAnimation: CodebookMotion.chartStyleSwap,
            minSegmentWidth: 84
        ) { option, isSelected in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
            .accessibilityLabel(option.title)
        }
        .fixedSize()
    }
}

/// Bars vs Squares as SF Symbols (provider sub-cards).
struct DashboardChartIconSegmentedControl: View {
    @Binding var selection: DashboardChartStyle

    var body: some View {
        SidebarStyleSegmentedControl(
            selection: $selection,
            options: DashboardChartStyle.allCases,
            minSegmentWidth: 38
        ) { option, isSelected in
            Image(systemName: option.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                .accessibilityLabel(option.title)
        }
    }
}

enum BarChartRange: String, CaseIterable {
    case week
    case month
    case quarter
    case half

    var title: String {
        switch self {
        case .week: return "7d"
        case .month: return "28d"
        case .quarter: return "3m"
        case .half: return "6m"
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 28
        case .quarter: return 90
        case .half: return 182
        }
    }
}
