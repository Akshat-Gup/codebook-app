import SwiftUI

struct OnboardingView: View {
    let startSetup: () -> Void
    let finish: () -> Void

    @State private var selection = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    OnboardingPageView(page: pages[selection], index: selection)
                        .id(selection)
                        .transition(.opacity.combined(with: .scale(scale: 0.992, anchor: .center)))
                }
                .animation(CodebookMotion.pane, value: selection)

                footer
            }

            Button {
                finish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(ControlChrome.glassButtonBackground(cornerRadius: 7))
            .help("Close")
            .accessibilityLabel("Close")
            .padding(24)
        }
        .background(Color.white)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == selection ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: index == selection ? 20 : 7, height: 7)
                        .animation(.snappy(duration: 0.22), value: selection)
                }
            }
            .frame(width: 58, alignment: .leading)

            Spacer()

            Button {
                if selection == 0 {
                    finish()
                } else {
                    withAnimation(.snappy(duration: 0.24)) {
                        selection -= 1
                    }
                }
            } label: {
                Text(selection == 0 ? "Skip" : "Back")
                    .frame(width: 72)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                if selection == pages.count - 1 {
                    startSetup()
                } else {
                    withAnimation(.snappy(duration: 0.24)) {
                        selection += 1
                    }
                }
            } label: {
                Label(
                    selection == pages.count - 1 ? "Open Settings" : "Next",
                    systemImage: selection == pages.count - 1 ? "gearshape" : "arrow.right"
                )
                .frame(width: 132)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 18)
        .background(Color.white)
    }
}

private struct OnboardingPage: Identifiable {
    enum Graphic {
        case welcome
        case sources
        case commits
        case search
    }

    let id = UUID()
    let title: String
    let body: String
    let graphic: Graphic

    static let pages = [
        OnboardingPage(
            title: "Catch up fast",
            body: "Trying to understand a PR or a repo? Codebook shows the AI chats that helped make the code.",
            graphic: .welcome
        ),
        OnboardingPage(
            title: "Share what worked",
            body: "Save good prompts and share them with your team, so nobody has to guess how something was built.",
            graphic: .sources
        ),
        OnboardingPage(
            title: "See your AI usage",
            body: "See which projects you use AI on, what tools you use most, and which prompts were actually useful.",
            graphic: .commits
        ),
        OnboardingPage(
            title: "Do more with your history",
            body: "Find old prompts, make diagrams, get simple tips, and download skills for better answers next time.",
            graphic: .search
        )
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    CodebookOnboardingMark()
                        .frame(width: 30, height: 30)

                    Text("Codebook")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                Text(page.title)
                    .font(.system(size: 34, weight: .semibold))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                OnboardingFeatureList(index: index)
            }
            .frame(width: 330, alignment: .leading)
            .padding(.leading, 48)
            .padding(.trailing, 34)
            .padding(.vertical, 34)

            Divider()

            OnboardingGraphicSurface(graphic: page.graphic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct OnboardingFeatureList: View {
    let index: Int

    private var rows: [(String, String)] {
        switch index {
        case 0:
            return [
                ("doc.text.magnifyingglass", "Understand PRs"),
                ("folder", "Learn new repos"),
                ("arrow.triangle.branch", "See what changed")
            ]
        case 1:
            return [
                ("bookmark", "Save prompts"),
                ("square.and.arrow.up", "Share with teammates"),
                ("message", "Keep the whole chat")
            ]
        case 2:
            return [
                ("chart.xyaxis.line", "See usage"),
                ("sparkles", "Get tips"),
                ("magnifyingglass", "Find old prompts")
            ]
        default:
            return [
                ("square.grid.2x2", "Download skills"),
                ("point.3.connected.trianglepath", "Make diagrams"),
                ("terminal", "Use the CLI")
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.1) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(row.1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

private struct OnboardingGraphicSurface: View {
    let graphic: OnboardingPage.Graphic

    var body: some View {
        ZStack {
            Color.white

            switch graphic {
            case .welcome:
                PromptConstellationGraphic()
            case .sources:
                SourceScanGraphic()
            case .commits:
                CommitTimelineGraphic()
            case .search:
                SearchShareGraphic()
            }
        }
    }
}

private struct PromptConstellationGraphic: View {
    var body: some View {
        ZStack {
            OnboardingSoftGrid()

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    MetricTile(title: "Chats", value: "428")
                    MetricTile(title: "Repos", value: "18")
                    MetricTile(title: "Commits", value: "742")
                }

                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                            )
                            .frame(width: 180, height: 68)
                            .offset(x: cardOffset(index).x, y: cardOffset(index).y)
                            .rotationEffect(.degrees(cardRotation(index)))
                            .shadow(color: Color.black.opacity(0.10), radius: 12, y: 8)
                            .overlay(alignment: .leading) {
                                PromptCardContent(index: index)
                                    .frame(width: 180, height: 68, alignment: .leading)
                                    .offset(x: cardOffset(index).x, y: cardOffset(index).y)
                                    .rotationEffect(.degrees(cardRotation(index)))
                            }
                    }

                    CodebookOnboardingMark()
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.accentColor.opacity(0.24), radius: 22)
                }
                .frame(width: 360, height: 250)
            }
        }
        .padding(36)
    }

    private func cardOffset(_ index: Int) -> CGPoint {
        [
            CGPoint(x: -86, y: -74),
            CGPoint(x: 92, y: -56),
            CGPoint(x: -92, y: 78),
            CGPoint(x: 86, y: 72)
        ][index]
    }

    private func cardRotation(_ index: Int) -> Double {
        [-7, 5, 6, -4][index]
    }
}

private struct SourceScanGraphic: View {
    var body: some View {
        ZStack {
            OnboardingSoftGrid()

            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    ForEach(SourceNode.sample) { source in
                        VStack(spacing: 9) {
                            Image(systemName: source.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 52, height: 52)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Text(source.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 76)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(SourceProgress.sample) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 26, height: 26)
                                .background(Color.accentColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(item.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.secondary.opacity(0.16))
                                        .overlay(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.78))
                                                .frame(width: geo.size.width * item.progress)
                                        }
                                }
                                .frame(height: 6)
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                    }
                }
                .frame(width: 360)
            }
        }
        .padding(36)
    }
}

private struct CommitTimelineGraphic: View {
    var body: some View {
        ZStack {
            OnboardingSoftGrid()

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 0) {
                    ForEach(CommitNode.sample.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            Circle()
                                .fill(index == 1 ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))

                            if index < CommitNode.sample.count - 1 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.20))
                                    .frame(width: 2, height: 78)
                            }
                        }
                    }
                }
                .padding(.top, 16)

                VStack(spacing: 12) {
                    ForEach(CommitNode.sample) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
                                .frame(width: 28, height: 28)
                                .background((item.isSelected ? Color.accentColor : Color.secondary).opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                Text(item.meta)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 5) {
                                    ForEach(0..<item.promptCount, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.20))
                                            .frame(width: 32, height: 8)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(13)
                        .frame(width: 350)
                        .background(item.isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .textBackgroundColor).opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(item.isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(36)
    }
}

private struct SearchShareGraphic: View {
    var body: some View {
        ZStack {
            OnboardingSoftGrid()

            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("auth session rotation")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("⌘K")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .padding(14)
                .frame(width: 380)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )

                VStack(spacing: 10) {
                    ForEach(SearchResult.sample) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
                                .frame(width: 28, height: 28)
                                .background((item.isSelected ? Color.accentColor : Color.secondary).opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                Text(item.meta)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: item.isSelected ? "square.and.arrow.up" : "star")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
                        }
                        .padding(12)
                        .frame(width: 360)
                        .background(item.isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .textBackgroundColor).opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(36)
    }
}

private struct CodebookOnboardingMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))

            Image(systemName: "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct OnboardingSoftGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }

            context.stroke(path, with: .color(Color.secondary.opacity(0.06)), lineWidth: 1)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(12)
        .frame(width: 100, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }
}

private struct PromptCardContent: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: ["sparkles", "terminal", "cursorarrow.rays", "chevron.left.forwardslash.chevron.right"][index])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(["Claude", "Codex", "Cursor", "Copilot"][index])
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            PreviewTextLine(width: [116, 130, 104, 122][index])
            PreviewTextLine(width: [82, 96, 126, 88][index])
        }
        .padding(12)
    }
}

private struct SourceNode: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    static let sample = [
        SourceNode(title: "Cursor", icon: "cursorarrow.rays"),
        SourceNode(title: "Claude", icon: "sparkles"),
        SourceNode(title: "Copilot", icon: "chevron.left.forwardslash.chevron.right"),
        SourceNode(title: "Codex", icon: "terminal")
    ]
}

private struct SourceProgress: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let value: String
    let progress: CGFloat

    static let sample = [
        SourceProgress(title: "Saved prompts", icon: "bookmark", value: "42", progress: 0.74),
        SourceProgress(title: "Shared with team", icon: "square.and.arrow.up", value: "16", progress: 0.48),
        SourceProgress(title: "Full chats kept", icon: "message", value: "128", progress: 0.82)
    ]
}

private struct CommitNode: Identifiable {
    let id = UUID()
    let title: String
    let meta: String
    let icon: String
    let promptCount: Int
    var isSelected = false

    static let sample = [
        CommitNode(title: "Better prompt ideas", meta: "tip · 12 useful rewrites", icon: "sparkles", promptCount: 3),
        CommitNode(title: "Busy project this week", meta: "usage · 3 projects active", icon: "chart.xyaxis.line", promptCount: 4, isSelected: true),
        CommitNode(title: "Same task keeps coming up", meta: "idea · save it as a skill", icon: "repeat", promptCount: 2)
    ]
}

private struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let meta: String
    let icon: String
    var isSelected = false

    static let sample = [
        SearchResult(title: "Review a new PR", meta: "Skill · understand changes faster", icon: "square.grid.2x2", isSelected: true),
        SearchResult(title: "Make a code diagram", meta: "Diagram · explain how it works", icon: "point.3.connected.trianglepath"),
        SearchResult(title: "Reuse a release note prompt", meta: "CLI · saved prompt", icon: "terminal")
    ]
}

private struct PreviewTextLine: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.secondary.opacity(0.22))
            .frame(width: width, height: 7)
    }
}
