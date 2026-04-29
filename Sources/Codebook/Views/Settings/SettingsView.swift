import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    private static let shareCardAnimationInterval = 1.0 / 12.0
    private static let defaultShareCardHoverPoint = CGPoint(x: 0.5, y: 0.5)
    private static let shareCardHoverPrecision: CGFloat = 1.0 / 36.0

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updaterController: SparkleUpdaterController
    @Environment(\.dismiss) private var dismiss
    @State private var insightsApiKeyDraft = ""
    @State private var draftsLoaded = false
    @State private var isShareCardHovered = false
    @State private var isCopyButtonHovered = false
    @State private var copiedProfileCardImage = false
    @State private var shareCardHoverPoint: CGPoint = SettingsView.defaultShareCardHoverPoint
    @State private var profileSnapshot = ProfileCardSnapshotBuilder.build(prompts: [], displayName: "")

    var body: some View {
        HSplitView {
            settingsProfileColumn
            settingsOptionsColumn
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            )
            .help("Close Settings")
            .accessibilityLabel("Close Settings")
            .keyboardShortcut(.cancelAction)
            .padding(.top, 16)
            .padding(.trailing, 24)
        }
        .frame(minWidth: 940, minHeight: 640)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if !draftsLoaded {
                model.loadInsightsApiKeyIfNeeded()
                reloadDrafts()
                draftsLoaded = true
            }
            rebuildProfileSnapshot()
        }
        .onChange(of: model.insightsApiKey) { _, newValue in
            guard draftsLoaded else { return }
            insightsApiKeyDraft = newValue
        }
        .onChange(of: model.importedPromptsRevision) { _, _ in
            rebuildProfileSnapshot()
        }
    }

    private var settingsProfileColumn: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 16) {
                TimelineView(.periodic(from: .now, by: Self.shareCardAnimationInterval)) { context in
                    GeometryReader { proxy in
                        let rotationX = isShareCardHovered ? (0.5 - shareCardHoverPoint.y) * 10 : 0
                        let rotationY = isShareCardHovered ? (shareCardHoverPoint.x - 0.5) * 12 : 0
                        let contourPhase = CGFloat(context.date.timeIntervalSinceReferenceDate) * 0.55

                        ProfileShareCardView(snapshot: profileSnapshot, contourPhase: contourPhase)
                            .scaleEffect(isShareCardHovered ? 1.018 : 1)
                            .rotation3DEffect(.degrees(rotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
                            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                            .shadow(color: Color.black.opacity(isShareCardHovered ? 0.34 : 0.18), radius: isShareCardHovered ? 30 : 18, y: isShareCardHovered ? 18 : 8)
                            .shadow(color: Color(red: 0.35, green: 0.75, blue: 0.98).opacity(isShareCardHovered ? 0.14 : 0), radius: 28, y: 12)
                            .animation(CodebookMotion.hover, value: isShareCardHovered)
                            .onContinuousHover { phase in
                                updateShareCardHover(phase, in: proxy.size)
                            }
                    }
                }
                .frame(width: 320, height: 480)

                Button {
                    copyProfileCardImage()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copiedProfileCardImage ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                        Text(copiedProfileCardImage ? "Copied" : "Copy Image")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(copiedProfileCardImage ? Color.green.opacity(0.85) : Color.black.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                copiedProfileCardImage
                                    ? Color.green.opacity(isCopyButtonHovered ? 0.26 : 0.18)
                                    : Color.black.opacity(isCopyButtonHovered ? 0.10 : 0.06),
                                lineWidth: 1
                            )
                    }
                    .scaleEffect(isCopyButtonHovered ? 1.01 : 1)
                    .shadow(color: Color.black.opacity(isCopyButtonHovered ? 0.12 : 0.06), radius: isCopyButtonHovered ? 10 : 4, y: isCopyButtonHovered ? 4 : 2)
                }
                .buttonStyle(.plain)
                .animation(CodebookMotion.hover, value: isCopyButtonHovered)
                .onHover { hovering in
                    isCopyButtonHovered = hovering
                }
            }
            .frame(maxWidth: 320)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .overlay(Color.black.opacity(0.02))
        )
    }

    private var settingsOptionsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                updatesPane

                aiSettingsPane
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var updatesPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSectionHeader(
                icon: "arrow.triangle.2.circlepath",
                title: "Software Updates"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Version")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(model.appVersionDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }

                Button {
                    updaterController.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Check for Updates")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        updaterController.canCheckForUpdates
                            ? Color.accentColor
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .foregroundStyle(updaterController.canCheckForUpdates ? Color.white : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!updaterController.canCheckForUpdates)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var aiSettingsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSectionHeader(
                icon: "sparkle.magnifyingglass",
                title: "AI & API"
            )

            VStack(alignment: .leading, spacing: 14) {
                if apiKeySavedAndUnchanged {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green)
                        Text("Key saved in Keychain")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
                    )
                    .accessibilityLabel("API key saved in Keychain")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(InsightsProvider.allCases, id: \.self) { provider in
                            Button {
                                model.persistInsightsApiProvider(provider.rawValue)
                            } label: {
                                Label(provider.title, systemImage: provider.menuSystemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedInsightsProvider.menuSystemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedInsightsProvider.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    SecureField(selectedInsightsProvider.keyPlaceholder, text: $insightsApiKeyDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                }

                Button {
                    model.saveInsightsApiKey(insightsApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Save to Keychain")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(apiKeySavedAndUnchanged ? Color(nsColor: .controlBackgroundColor) : Color.accentColor)
                    .foregroundStyle(apiKeySavedAndUnchanged ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(apiKeySavedAndUnchanged)
                .help(apiKeySavedAndUnchanged ? "Change the key to enable Save." : "Save to Keychain")

                Text(model.insightsAvailabilityHelpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func settingsSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    /// True when a non-empty key is stored and the text field still matches it (initial open or after save).
    private var apiKeySavedAndUnchanged: Bool {
        let trimmedDraft = insightsApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSaved = model.insightsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedSaved.isEmpty && trimmedDraft == trimmedSaved
    }

    private var selectedInsightsProvider: InsightsProvider {
        model.selectedInsightsProvider
    }

    private func reloadDrafts() {
        insightsApiKeyDraft = model.insightsApiKey
    }

    private func copyProfileCardImage() {
        ProfileCardImageExport.copyImageToPasteboard(snapshot: profileSnapshot)
        copiedProfileCardImage = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedProfileCardImage = false
        }
    }

    private func updateShareCardHover(_ phase: HoverPhase, in size: CGSize) {
        switch phase {
        case .active(let location):
            isShareCardHovered = true
            let point = normalizedShareCardHoverPoint(for: location, in: size)
            if point != shareCardHoverPoint {
                shareCardHoverPoint = point
            }
        case .ended:
            isShareCardHovered = false
            shareCardHoverPoint = Self.defaultShareCardHoverPoint
        }
    }

    private func normalizedShareCardHoverPoint(for location: CGPoint, in size: CGSize) -> CGPoint {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let x = min(max(location.x / width, 0), 1)
        let y = min(max(location.y / height, 0), 1)
        return CGPoint(
            x: quantizeShareCardHoverValue(x),
            y: quantizeShareCardHoverValue(y)
        )
    }

    private func quantizeShareCardHoverValue(_ value: CGFloat) -> CGFloat {
        (value / Self.shareCardHoverPrecision).rounded() * Self.shareCardHoverPrecision
    }

    private func rebuildProfileSnapshot() {
        profileSnapshot = ProfileCardSnapshotBuilder.build(prompts: model.importedPrompts, displayName: "")
    }
}

enum ViewFormatters {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let usdCurrency2: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let usdCurrency4: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        return formatter
    }()
}

struct DashboardDerivedData {
    let heatmapStats: [DailyPromptStat]
    let structuredPromptCount: Int
    let structuredPromptRate: Int
    let projectCount: Int
    let providerStats: [ProviderStat]
    let providerMiniCharts: [ProviderMiniChartData]
    let activeHeatmapDays: Int
    let currentStreak: Int
    let bestDayStat: DailyPromptStat?
    let bestDayLabel: String

    static let empty = DashboardDerivedData(
        heatmapStats: [],
        structuredPromptCount: 0,
        structuredPromptRate: 0,
        projectCount: 0,
        providerStats: [],
        providerMiniCharts: [],
        activeHeatmapDays: 0,
        currentStreak: 0,
        bestDayStat: nil,
        bestDayLabel: "no data yet"
    )
}
