import SwiftUI

// MARK: - Motion

/// Shared animation curves so navigation, lists, and disclosures feel cohesive.
enum CodebookMotion {
    /// List selection, detail header, search tabs.
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Disclosures and small toggles.
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.88)
    /// Sidebar mode changes and main split-pane content.
    static let pane = Animation.spring(response: 0.44, dampingFraction: 0.91)
    /// Focus rings, hovers, and fills without overshoot.
    static let gentle = Animation.smooth(duration: 0.22)
    /// Dashboard hover highlights.
    static let hover = Animation.easeOut(duration: 0.14)
    /// Bar chart crosshair + tooltip (snappy; avoids sluggish pointer tracking).
    static let chartPlotHover = Animation.easeOut(duration: 0.06)
    /// Bars ↔ Squares and other dashboard chart style swaps.
    static let chartStyleSwap = Animation.spring(response: 0.42, dampingFraction: 0.84)
    /// Sidebar row selection, hover, and pin chrome (single curve avoids stacked animations fighting).
    static let sidebarChrome = Animation.spring(response: 0.38, dampingFraction: 0.88)
    /// Keyword vs AI toggle pill.
    static let sidebarSwitch = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// Pinned / Hidden rows appearing or disappearing.
    static let sidebarList = Animation.spring(response: 0.36, dampingFraction: 0.90)
}

extension AnyTransition {
    static var sidebarSection: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}

/// Repo rows: pin + menu live in an overlay so `Menu` never compresses counts; gap separates count from that cluster.
/// All Projects uses a narrow trailing group (count + add) instead of the two-icon column width.
enum SidebarMetrics {
    static let actionColumn: CGFloat = 44
    static let rowSpacing: CGFloat = 6
    static let countToActionGap: CGFloat = 10
}

/// Tab selection for the Agents sheet file preview.
enum AgentsFileTab: String, CaseIterable, Hashable {
    case agentsMD
    case claudeMD

    var title: String {
        switch self {
        case .agentsMD: return "AGENTS.md"
        case .claudeMD: return "CLAUDE.md"
        }
    }

    var fileName: String {
        switch self {
        case .agentsMD: return "AGENTS.md"
        case .claudeMD: return "CLAUDE.md"
        }
    }
}
