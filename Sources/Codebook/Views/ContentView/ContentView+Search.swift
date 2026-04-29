import SwiftUI

extension ContentView {

    // MARK: - Search Tabs

    var searchTabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SearchTab.allCases, id: \.self) { tab in
                        searchTabButton(tab)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollClipDisabled()

            if let loadingTab = model.searchTabLoading, loadingTab == model.searchTab {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .padding(.trailing, 12)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    func searchTabButton(_ tab: SearchTab) -> some View {
        let isSelected = model.searchTab == tab
        let count = model.searchTabCounts[tab] ?? 0

        return Button {
            withAnimation(CodebookMotion.standard) {
                model.selectSearchTab(tab)
            }
        } label: {
            HStack(spacing: 7) {
                if tab != .all {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                if count > 0 || tab == .all {
                    Text(formattedSearchTabCount(count))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            isSelected
                            ? AnyShapeStyle(.primary.opacity(0.86))
                            : AnyShapeStyle(.tertiary)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                        ? Color.accentColor.opacity(0.13)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.65)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? Color.accentColor.opacity(0.26)
                        : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.08) : .clear, radius: 6, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title) \(count)")
        .animation(CodebookMotion.standard, value: model.searchTab)
    }

    func formattedSearchTabCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    // MARK: - AI Search Results

    @ViewBuilder
    var aiSearchResultsPane: some View {
        Divider().opacity(0.5)

        if model.searchInputText.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text("AI Search")
                    .font(.subheadline.weight(.semibold))
                Text("Type a query and press Enter to search with AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.aiSearchIsRunning {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching with AI…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if let reasoning = model.aiSearchReasoning {
                        aiSearchReasoningCard(reasoning: reasoning, isRunning: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.aiSearchError {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.insightsAIAvailable && model.aiSearchResults.isEmpty {
            ContentUnavailableView("No results", systemImage: "sparkles.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.insightsAIAvailable {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "key")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(model.insightsEmptyStateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Open Settings") {
                    model.settingsPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let reasoning = model.aiSearchReasoning {
                        aiSearchReasoningCard(reasoning: reasoning)
                    }

                    if let summary = model.aiSearchSummary {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                Text("Summary")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .padding(.horizontal, 12)
                    }

                    // Results count
                    Text("\(model.aiSearchResults.count) results")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    // Prompt rows (same style as regular search)
                    ForEach(model.aiSearchResults) { prompt in
                        promptRowButton(prompt, diffContextPrompts: model.aiSearchResults)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    func aiSearchReasoningCard(reasoning: String, isRunning: Bool = false) -> some View {
        if isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Reasoning")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 12)
        } else {
            DisclosureGroup {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                    Text("Reasoning")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Search Result Views

    var searchResultsAll: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                Text("\(model.visiblePrompts.count) results")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(model.visiblePrompts) { prompt in
                    promptRowButton(prompt, diffContextPrompts: model.visiblePrompts)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    var searchResultsByCommits: some View {
        if model.searchTabLoading == .commits && model.searchByCommits.isEmpty {
            searchResultsLoading
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.searchByCommits, id: \.key) { group in
                        searchGroupCard(
                            icon: group.sha != nil ? "arrow.triangle.branch" : "tray",
                            title: group.message,
                            badge: group.sha.map { String($0.prefix(7)) },
                            prompts: group.prompts
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    var searchResultsByDates: some View {
        if model.searchTabLoading == .dates && model.searchByDates.isEmpty {
            searchResultsLoading
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.searchByDates, id: \.key) { group in
                        dateSearchGroupCard(group)
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    var searchResultsByProjects: some View {
        if model.searchTabLoading == .projects && model.searchByProjects.isEmpty {
            searchResultsLoading
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.searchByProjects, id: \.key) { group in
                        searchGroupCard(
                            icon: "folder",
                            title: group.name,
                            badge: nil,
                            prompts: group.prompts
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    var searchResultsByTags: some View {
        if model.searchTabLoading == .tags && model.searchByTags.isEmpty {
            searchResultsLoading
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.searchByTags, id: \.tag) { group in
                        searchGroupCard(
                            icon: "tag",
                            title: group.tag,
                            badge: nil,
                            prompts: group.prompts
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    var searchResultsByProviders: some View {
        if model.searchTabLoading == .providers && model.searchByProviders.isEmpty {
            searchResultsLoading
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.searchByProviders, id: \.provider) { group in
                        providerSearchGroupCard(group)
                    }
                }
                .padding(14)
            }
        }
    }

    var searchResultsLoading: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func searchGroupCard(icon: String, title: String, badge: String?, prompts: [ImportedPrompt]) -> some View {
        let commitDiffPromptIDs = icon == "arrow.triangle.branch" ? PromptThreading.latestCommitDiffPromptIDs(in: prompts) : Set<String>()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 14, height: 14)
                highlightedText(title, searchTerms: model.searchText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let badge = badge {
                    Text(badge)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    if let lead = prompts.first {
                        searchGroupCommitDiffTrailing(lead)
                    }
                }
                Spacer()
                Text(costLabel(for: prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(responseTimeLabel(for: prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(prompts.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if icon == "arrow.triangle.branch", let sha = prompts.first?.commitSHA {
                    commitActionButtons(sha: sha, prompts: prompts)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                promptRowButton(
                    prompt,
                    diffContextPrompts: prompts,
                    showsCommitDiff: icon == "arrow.triangle.branch" ? commitDiffPromptIDs.contains(prompt.id) : nil
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func dateSearchGroupCard(_ group: SearchDateGroup) -> some View {
        let prompts = group.prompts

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 14, height: 14)
                highlightedText(group.title, searchTerms: model.searchText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(costLabel(for: prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(responseTimeLabel(for: prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(prompts.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                dayActionButtons(prompts: prompts, dayKey: group.key, iconSize: 20)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                promptRowButton(prompt, diffContextPrompts: prompts)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func providerSearchGroupCard(_ group: SearchProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                PlatformIconView(provider: group.provider, size: 14)
                highlightedText(group.provider.title, searchTerms: model.searchText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(costLabel(for: group.prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(responseTimeLabel(for: group.prompts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(group.prompts.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(Array(group.prompts.enumerated()), id: \.element.id) { index, prompt in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                promptRowButton(prompt, diffContextPrompts: group.prompts)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Search Highlighting

    /// Builds an AttributedString with exact search term matches highlighted.
    func highlightedText(_ text: String, searchTerms: String) -> Text {
        guard !searchTerms.isEmpty else { return Text(text) }

        let tokens = searchTerms.lowercased().split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return Text(text) }

        let lowerText = text.lowercased()
        var highlights: [(Range<String.Index>, String)] = []

        for token in tokens {
            var searchStart = lowerText.startIndex
            while searchStart < lowerText.endIndex,
                  let range = lowerText.range(of: token, range: searchStart..<lowerText.endIndex) {
                let originalRange = text.index(range.lowerBound, offsetBy: 0)..<text.index(range.upperBound, offsetBy: 0)
                highlights.append((originalRange, String(text[originalRange])))
                searchStart = range.upperBound
            }
        }

        guard !highlights.isEmpty else { return Text(text) }

        // Sort by position and merge overlapping ranges
        let sorted = highlights.sorted { $0.0.lowerBound < $1.0.lowerBound }
        var merged: [Range<String.Index>] = []
        for (range, _) in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                let newEnd = max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = last.lowerBound..<newEnd
            } else {
                merged.append(range)
            }
        }

        // Build text with highlighted segments
        var result = Text("")
        var cursor = text.startIndex
        for range in merged {
            if cursor < range.lowerBound {
                result = result + Text(text[cursor..<range.lowerBound])
            }
            result = result + Text(text[range])
                .foregroundColor(.accentColor)
                .fontWeight(.semibold)
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result = result + Text(text[cursor..<text.endIndex])
        }
        return result
    }
}
