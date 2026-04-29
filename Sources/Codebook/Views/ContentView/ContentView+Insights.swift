import SwiftUI
import Charts

extension ContentView {

    // MARK: - Insights

    @ViewBuilder
    var insightsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header (centered, matching Plugins page)
                Text("Insights")
                    .font(.largeTitle.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)

                // No-key banner
                if !model.insightsAIAvailable {
                    HStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                        Text("No API key configured.")
                            .font(.system(size: 12, weight: .medium))
                        Text(model.insightsAvailabilityHelpText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            model.settingsPresented = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                    )
                }

                // ── Prompt Patterns card ──────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Prompt Patterns")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Patterns across prompts you have imported into Codebook")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Button {
                        model.runInsightsAnalysis()
                    } label: {
                        HStack(spacing: 6) {
                            if model.insightsIsRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 12))
                            }
                            Text(model.insightsIsRunning ? "Analyzing…" : "Analyze Prompting Patterns")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(model.insightsAIAvailable ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(model.insightsAIAvailable ? Color.white : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.insightsIsRunning || !model.insightsAIAvailable)

                    if let error = model.insightsError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let result = model.insightsResult {
                        insightsResultSection(
                            title: "Better Prompting",
                            subtitle: "How you could've prompted more effectively across your recent imported prompts",
                            systemImage: "text.badge.star",
                            items: result.betterPrompts
                        )
                        insightsResultSection(
                            title: "Strategies",
                            subtitle: "Repo-level ways to improve your AI-assisted workflow",
                            systemImage: "map",
                            items: result.strategies
                        )
                        insightsResultSection(
                            title: "Skills & Automations",
                            subtitle: "Recurring patterns you could turn into reusable skills",
                            systemImage: "bolt.fill",
                            items: result.skills
                        )
                        Text("Analyzed \(result.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
                }

                // ── Local Prompt Review card ────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Local Changes: Prompt Review")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Repositories with uncommitted changes or commits not on the remote yet")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    insightsRepositorySelector

                    Button {
                        model.analyzeLocalChanges()
                    } label: {
                        HStack(spacing: 6) {
                            if model.localChangesIsRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 12))
                            }
                            Text(model.localChangesIsRunning ? "Analyzing…" : "Analyze Local Prompt")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(model.insightsAIAvailable ? Color.accentColor.opacity(0.9) : Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(model.insightsAIAvailable ? Color.white : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.localChangesIsRunning || !model.insightsAIAvailable)
                    .help(model.insightsAIAvailable ? "Diff-based prompt tips and issue hints for the selected repo" : model.insightsAvailabilityHelpText)

                    if let error = model.localChangesError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let result = model.localChangesResult {
                        insightsResultSection(
                            title: "Prompt Suggestions",
                            subtitle: "Specific prompts tailored to your current changes",
                            systemImage: "text.badge.checkmark",
                            items: result.betterPrompts
                        )
                        insightsResultSection(
                            title: "Development Strategies",
                            subtitle: "How to approach this work more effectively",
                            systemImage: "map",
                            items: result.strategies
                        )
                        insightsResultSection(
                            title: "Automation Ideas",
                            subtitle: "Patterns worth automating based on this diff",
                            systemImage: "bolt.fill",
                            items: result.skills
                        )
                        Text("Analyzed \(result.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1.5)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var selectedLocalChangesProject: ProjectSummary? {
        if let selectedID = model.localChangesProjectID,
           let match = model.localChangesProjectOptions.first(where: { $0.id == selectedID }) {
            return match
        }
        return model.localChangesProjectOptions.first
    }

    var insightsRepositorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedLocalChangesProject == nil {
                Text("Choose a project below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.localChangesProjectOptions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: model.localChangesProjectOptions.isEmpty ? "tray" : "checkmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.localChangesProjectOptions.isEmpty ? "No repositories available" : "No pending local changes")
                            .font(.system(size: 12, weight: .semibold))
                        Text(model.localChangesProjectOptions.isEmpty ? "Add a folder from the sidebar." : "Every tracked repo is clean and in sync with its upstream, or has no upstream set.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.75)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.localChangesProjectOptions) { project in
                            insightsRepositoryCard(project)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .clipped()
            }
        }
    }

    func insightsRepositoryCard(_ project: ProjectSummary) -> some View {
        let isSelected = selectedLocalChangesProject?.id == project.id
        let isHovered = hoveredInsightsProjectID == project.id
        let accent = Color.accentColor

        return Button {
            model.selectLocalChangesProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(isSelected ? 0.9 : 0.65), accent.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: project.isManual ? "pin.fill" : "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white : accent)
                    }
                    .frame(width: 34, height: 34)

                    Spacer(minLength: 0)

                    if isSelected {
                        Text("Selected")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(accent.opacity(0.14))
                            )
                    } else {
                        Text("\(project.promptCount)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(insightsRepositoryPathLabel(for: project.path))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label(project.isManual ? "Manual" : "Tracked", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                    Text(project.promptCount == 1 ? "1 prompt" : "\(project.promptCount) prompts")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 228, alignment: .leading)
            .background(insightsRepositoryCardBackground(isSelected: isSelected, isHovered: isHovered, accent: accent))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.localChangesIsRunning)
        .onHover { hovering in
            hoveredInsightsProjectID = hovering ? project.id : nil
        }
        .help(project.path ?? project.name)
    }

    @ViewBuilder
    func insightsRepositoryCardBackground(isSelected: Bool, isHovered: Bool, accent: Color) -> some View {
        let fillColors = isSelected
            ? [accent.opacity(0.2), Color(nsColor: .textBackgroundColor)]
            : [Color(nsColor: .textBackgroundColor), Color(nsColor: .controlBackgroundColor)]
        let strokeColor = isSelected
            ? accent.opacity(0.42)
            : Color(nsColor: .separatorColor).opacity(isHovered ? 0.36 : 0.22)

        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: fillColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                    .padding(1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isSelected ? 1.2 : 0.9)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 14 : 8, x: 0, y: isSelected ? 8 : 4)
    }

    func insightsRepositoryPathLabel(for path: String?) -> String {
        guard let path else { return "Imported prompt history" }
        let components = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        return components.suffix(4).joined(separator: "/")
    }

    func insightsResultSection(title: String, subtitle: String, systemImage: String, items: [InsightItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 17)
            }

            if items.isEmpty {
                Text("Nothing to show.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.horizontal, 14) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let example = item.example {
                                Text(example)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
