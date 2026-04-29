import SwiftUI

// MARK: - Shared Card Chrome

/// Standard card background used across the app (Plugins, Insights, Automations, etc.).
enum CardChrome {
    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16

    @ViewBuilder
    static func cardBackground(cornerRadius: CGFloat = CardChrome.cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
    }

    @ViewBuilder
    static func glassBackground(cornerRadius: CGFloat = CardChrome.cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
    }
}

// MARK: - Shared Control Chrome

/// Shared control styling constants used by both ContentView and EcosystemPane.
enum ControlChrome {
    /// Neutral fill for secondary buttons and segmented tracks.
    static let softSurface = Color(nsColor: .controlColor)
    /// Active segment / primary filled control.
    static let segmentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    /// Label on control surfaces.
    static let charcoal = Color(nsColor: .labelColor)

    @ViewBuilder
    static func glassButtonBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
    }
}

// MARK: - Card Section Icon

/// Standard icon badge used in card headers (Automations, Insights, etc.).
struct CardSectionIcon: View {
    let systemName: String
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size * 2.1, height: size * 2.1)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.53, style: .continuous))
    }
}
