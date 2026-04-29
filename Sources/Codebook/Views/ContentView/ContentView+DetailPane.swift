import SwiftUI

extension ContentView {

    // MARK: - Detail Pane

    @ViewBuilder
    var detailPane: some View {
        if let prompt = model.selectedPrompt {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header bar — provider, project, date, actions
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            PlatformIconView(provider: prompt.provider, size: 13)
                            if let vendor = ModelVendor.detect(modelID: prompt.modelID) {
                                ModelVendorIconView(vendor: vendor, size: 12)
                            }
                            Text(prompt.provider.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        Text("  /  ")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)

                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(prompt.projectName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Text(DateFormatting.displayString(from: prompt.capturedAt))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    Divider().opacity(0.5)

                    // Metadata strip — import metadata, git, tags
                    let promptCostEstimate = PromptCostEstimator.estimate(for: prompt)
                    let hasImportMetadata = prompt.modelID != nil
                        || prompt.inputTokens != nil
                        || prompt.cachedInputTokens != nil
                        || prompt.outputTokens != nil
                        || prompt.totalTokens != nil
                        || prompt.hasMeasuredResponseTime
                        || promptCostEstimate != nil
                    let hasCommit = prompt.commitSHA != nil
                    if hasImportMetadata || hasCommit || !prompt.displayTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if hasImportMetadata {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "shippingbox")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                        Text("Imported Metadata")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }

                                    FlowLayout(spacing: 5) {
                                        importMetadataPill(
                                            icon: "cpu",
                                            label: prompt.modelID ?? "No model"
                                        )
                                        if let tokenTotal = importMetadataTokenDisplayTotal(for: prompt) {
                                            ImportMetadataTokenSummary(
                                                prompt: prompt,
                                                total: tokenTotal,
                                                formatTokenCount: formatTokenCount
                                            )
                                        }
                                        if let promptCostEstimate {
                                            importMetadataPill(
                                                icon: "dollarsign.circle",
                                                label: "\(currencyString(promptCostEstimate.amountUSD)) estimated"
                                            )
                                        }
                                        if let responseTimeMs = prompt.responseTimeMs, responseTimeMs > 0 {
                                            importMetadataPill(
                                                icon: "timer",
                                                label: formatDuration(milliseconds: responseTimeMs)
                                            )
                                        }
                                    }
                                }
                            }

                            // Git commit row
                            if let sha = prompt.commitSHA {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 10))
                                        .foregroundStyle(prompt.commitOrphaned ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))

                                    Text(String(sha.prefix(7)))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(prompt.commitOrphaned ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))

                                    if let msg = prompt.commitMessage, !msg.isEmpty {
                                        Text(msg)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }

                                    if let confidence = prompt.commitConfidence {
                                        Text(confidence.title)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(confidenceColor(confidence))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(confidenceColor(confidence).opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }

                                    if prompt.commitOrphaned {
                                        Text("Orphaned")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }

                                    Spacer()

                                    commitActionButtons(sha: sha, prompts: [prompt])
                                }

                                if prompt.hasCommitLineStats {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chart.bar.doc.horizontal")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                        let ins = prompt.commitInsertions ?? 0
                                        let del = prompt.commitDeletions ?? 0
                                        if ins > 0 || del > 0 {
                                            Text("+\(ins)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Color.green)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Text("−\(del)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Color.red.opacity(0.9))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        if let files = prompt.commitFilesChanged, files > 0 {
                                            Text("\(files) files")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        Text("Commit-wide totals")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.quaternary)
                                        Spacer()
                                    }
                                    .padding(.leading, 16)
                                }

                                if prompt.commitOrphaned {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.orange)
                                        Text("This commit is no longer in the current git history for this repository.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 16)
                                }
                            }

                            if !prompt.displayTags.isEmpty {
                                FlowLayout(spacing: 5) {
                                    ForEach(prompt.displayTags.prefix(6), id: \.self) { tag in
                                        Text(tag)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                        Divider().opacity(0.5)
                    }

                    // Action bar — in the white zone, tied to the content below
                    HStack(spacing: 8) {
                        Button {
                            copyPrompt(prompt)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedPromptID == prompt.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(copiedPromptID == prompt.id ? "Copied" : "Copy")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        savePromptPillButton(prompt: prompt)
                        hidePromptPillButton(prompt: prompt)

                        if !prompt.metadataOnly {
                            // Refine with AI
                            Button {
                                model.refineImportedPrompt(prompt)
                            } label: {
                                HStack(spacing: 4) {
                                    if model.refiningImportedPromptID == prompt.id {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10))
                                    }
                                    Text("Refine")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(model.insightsAIAvailable ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(model.insightsAIAvailable ? Color.accentColor : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            model.insightsAIAvailable ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.4),
                                            lineWidth: 0.5
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.refiningImportedPromptID == prompt.id)
                            .help(model.insightsAIAvailable ? "Get an AI-refined version of this prompt" : model.insightsAvailabilityHelpText)

                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    // Prompt body — clean, no inner card
                    if prompt.metadataOnly {
                        Text("This source only exposes metadata right now.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                            .padding(20)
                    } else if !model.searchText.isEmpty {
                        highlightedText(prompt.body, searchTerms: model.searchText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.85))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    } else {
                        Text(prompt.body)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.85))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }

                    // Refined version (inline, below the original)
                    if let refined = model.refinedImportedPrompts[prompt.id] {
                        Divider().opacity(0.5)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text("Refined Version")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(refined, forType: .string)
                                } label: {
                                    Text("Copy")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                Button {
                                    model.dismissRefinedPrompt(prompt.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(refined)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.primary.opacity(0.85))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(20)
                        .background(Color.accentColor.opacity(0.04))
                        .overlay(
                            Rectangle()
                                .frame(width: 2)
                                .foregroundStyle(Color.accentColor.opacity(0.35)),
                            alignment: .leading
                        )
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .contentTransition(.interpolate)
            .animation(CodebookMotion.standard, value: model.selectedPromptID)
        } else if model.isRefreshing {
            VStack {
                Spacer()
                loadingStateView()
                    .frame(maxWidth: 320)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Selection", systemImage: "text.document")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    var savedPane: some View {
        VStack(spacing: 0) {
            historyFilterBar

            if model.savedDayGroups.isEmpty {
                ContentUnavailableView(model.hasActiveHistoryFilters ? "No saved items match the current filters" : "No saved items", systemImage: "bookmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(model.savedDayGroups.enumerated()), id: \.element.id) { index, day in
                            daySectionCard(day, isFirst: index == 0)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}
