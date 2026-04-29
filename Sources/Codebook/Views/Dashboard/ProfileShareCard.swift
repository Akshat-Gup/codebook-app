import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileDayActivity: Hashable, Sendable {
    var day: Date
    var count: Int
}

struct ProfileCardSnapshot: Hashable, Sendable {
    var displayName: String
    var initials: String
    var messages: Int
    var threads: Int
    var linesAdded: Int
    var linesRemoved: Int
    var linesChangedEstimate: Int
    var heatmapDays: [ProfileDayActivity]
    var maxHeatmapCount: Int
    var currentStreak: Int
}

enum ProfileCardSnapshotBuilder {
    private static let dayCount = 196

    static func build(prompts: [ImportedPrompt], displayName: String) -> ProfileCardSnapshot {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? (NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "You"
            : NSFullUserName()) : trimmedName

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else {
            return ProfileCardSnapshot(
                displayName: resolvedName,
                initials: initials(from: resolvedName),
                messages: prompts.count,
                threads: 0,
                linesAdded: 0,
                linesRemoved: 0,
                linesChangedEstimate: 0,
                heatmapDays: [],
                maxHeatmapCount: 1,
                currentStreak: 0
            )
        }

        var countsByDay: [Date: Int] = [:]
        for prompt in prompts {
            let day = calendar.startOfDay(for: prompt.effectiveDate)
            countsByDay[day, default: 0] += 1
        }

        var heatmap: [ProfileDayActivity] = []
        heatmap.reserveCapacity(dayCount)
        var cursor = start
        while cursor <= today {
            heatmap.append(ProfileDayActivity(day: cursor, count: countsByDay[cursor, default: 0]))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        let maxHeatmapCount = max(heatmap.map(\.count).max() ?? 1, 1)
        let currentStreak = heatmap.reversed().prefix { $0.count > 0 }.count

        var seenCommits = Set<String>()
        var added = 0
        var removed = 0
        var changedEst = 0
        for prompt in prompts {
            guard let sha = prompt.commitSHA, let root = prompt.gitRoot else { continue }
            let key = root + "\u{1f}" + sha
            guard seenCommits.insert(key).inserted else { continue }
            added += prompt.commitInsertions ?? 0
            removed += prompt.commitDeletions ?? 0
            changedEst += prompt.commitLinesChangedEstimate
        }

        let threadIDs = Set(prompts.map { p -> String in
            if let sid = p.sourceContextID, !sid.isEmpty {
                return p.provider.rawValue + "|" + sid + "|" + p.projectKey
            }
            return p.id
        })

        return ProfileCardSnapshot(
            displayName: resolvedName,
            initials: initials(from: resolvedName),
            messages: prompts.count,
            threads: max(threadIDs.count, 0),
            linesAdded: added,
            linesRemoved: removed,
            linesChangedEstimate: changedEst,
            heatmapDays: heatmap,
            maxHeatmapCount: maxHeatmapCount,
            currentStreak: currentStreak
        )
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            let a = parts[0].first.map(String.init) ?? ""
            let b = parts[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// The Codebook logo mark: chevron prompt, underscore, and vertical spine.
private struct CodebookMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        var p = Path()
        // Chevron: >
        p.move(to: CGPoint(x: 3.6 * sx, y: 6.25 * sy))
        p.addLine(to: CGPoint(x: 10.25 * sx, y: 10 * sy))
        p.addLine(to: CGPoint(x: 3.6 * sx, y: 13.75 * sy))
        // Underscore: _
        p.move(to: CGPoint(x: 3.6 * sx, y: 16.35 * sy))
        p.addLine(to: CGPoint(x: 11 * sx, y: 16.35 * sy))
        // Spine: |
        p.move(to: CGPoint(x: 12 * sx, y: 0))
        p.addLine(to: CGPoint(x: 12 * sx, y: rect.height))
        return p
    }
}

/// Share card; fixed aspect for raster export.
struct ProfileShareCardView: View {
    let snapshot: ProfileCardSnapshot
    var exportScale: CGFloat = 1
    var contourPhase: CGFloat = 0

    private let columns = 28
    private let cellSize: CGFloat = 7
    private let cellSpacing: CGFloat = 2
    private let accent = Color(red: 0.42, green: 0.76, blue: 1.0)
    private let cardBase = Color(red: 0.078, green: 0.082, blue: 0.09)
    private let separator = Color.white.opacity(0.08)
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        let cells = Array(snapshot.heatmapDays.suffix(columns * 7))

        VStack(alignment: .leading, spacing: 0) {
            // Avatar + Name
            HStack(alignment: .center, spacing: 10 * exportScale) {
                Text(snapshot.initials)
                    .font(.system(size: 16 * exportScale, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38 * exportScale, height: 38 * exportScale)
                    .background(accent.opacity(0.18))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(accent.opacity(0.32), lineWidth: 1 * exportScale)
                    )

                Text(snapshot.displayName)
                    .font(.system(size: 18 * exportScale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.bottom, 20 * exportScale)

            // Heatmap — directly on card, no sub-card
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize * exportScale), spacing: cellSpacing * exportScale), count: columns),
                spacing: cellSpacing * exportScale
            ) {
                ForEach(cells, id: \.day) { cell in
                    RoundedRectangle(cornerRadius: 1.8 * exportScale, style: .continuous)
                        .fill(heatColor(count: cell.count, max: snapshot.maxHeatmapCount))
                        .frame(width: cellSize * exportScale, height: cellSize * exportScale)
                }
            }
            .padding(.bottom, 20 * exportScale)

            // Stats grid — book-style 2×2 with thin separators
            let border = separator
            VStack(spacing: 1 * exportScale) {
                HStack(spacing: 1 * exportScale) {
                    bookCell(label: "Prompts", value: formatInt(snapshot.messages), sub: nil)
                    bookCell(label: "Sessions", value: formatInt(snapshot.threads), sub: nil)
                }
                .background(border)

                HStack(spacing: 1 * exportScale) {
                    bookCell(
                        label: "Net Lines",
                        value: signedInt(snapshot.linesAdded - snapshot.linesRemoved),
                        sub: "+\(formatInt(snapshot.linesAdded)) / −\(formatInt(snapshot.linesRemoved))"
                    )
                    bookCell(
                        label: "Streak",
                        value: "\(snapshot.currentStreak)",
                        sub: snapshot.currentStreak == 1 ? "day" : "days"
                    )
                }
                .background(border)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10 * exportScale, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10 * exportScale, style: .continuous)
                    .strokeBorder(separator, lineWidth: 1 * exportScale)
            )

            Spacer(minLength: 0)

            // Codebook branding — bottom right
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8 * exportScale) {
                    CodebookMarkShape()
                        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.6 * exportScale, lineCap: .round, lineJoin: .round))
                        .frame(width: 18 * exportScale, height: 18 * exportScale)

                    Text("Codebook")
                        .font(.system(size: 13 * exportScale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .padding(22 * exportScale)
        .frame(width: 320 * exportScale, height: 480 * exportScale, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24 * exportScale, style: .continuous))
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24 * exportScale, style: .continuous)
                .fill(cardBase)

            ContourFieldShape(phase: contourPhase, step: 6 * exportScale)
                .stroke(Color.white.opacity(0.08), lineWidth: 1 * exportScale)
                .clipShape(RoundedRectangle(cornerRadius: 24 * exportScale, style: .continuous))
        }
    }

    // MARK: – Book cell

    private func bookCell(label: String, value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3 * exportScale) {
            Text(label)
                .font(.system(size: 9 * exportScale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.36))
            Text(value)
                .font(.system(size: 18 * exportScale, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.system(size: 9 * exportScale, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 12 * exportScale)
        .padding(.vertical, 10 * exportScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBase)
    }

    // MARK: – Helpers

    private func heatColor(count: Int, max: Int) -> Color {
        guard count > 0 else { return Color.white.opacity(0.06) }
        let t = CGFloat(count) / CGFloat(max)
        return accent.opacity(0.2 + t * 0.8)
    }

    private func formatInt(_ n: Int) -> String {
        Self.integerFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func signedInt(_ n: Int) -> String {
        if n >= 0 { return "+\(formatInt(n))" }
        return "−\(formatInt(abs(n)))"
    }
}

private struct ContourFieldShape: Shape {
    var phase: CGFloat
    var step: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sampleStep = max(step, 6)
        let columns = max(Int(ceil(rect.width / sampleStep)), 2)
        let rows = max(Int(ceil(rect.height / sampleStep)), 2)

        var values = Array(repeating: CGFloat.zero, count: (columns + 1) * (rows + 1))

        func gridIndex(_ x: Int, _ y: Int) -> Int {
            y * (columns + 1) + x
        }

        for y in 0...rows {
            for x in 0...columns {
                let point = CGPoint(x: CGFloat(x) * sampleStep, y: CGFloat(y) * sampleStep)
                values[gridIndex(x, y)] = scalarField(at: point)
            }
        }

        let levels = stride(from: CGFloat(-1.05), through: CGFloat(1.05), by: CGFloat(0.065))

        for level in levels {
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * sampleStep
                    let y = CGFloat(row) * sampleStep

                    let bl = CGPoint(x: x, y: y + sampleStep)
                    let br = CGPoint(x: x + sampleStep, y: y + sampleStep)
                    let tr = CGPoint(x: x + sampleStep, y: y)
                    let tl = CGPoint(x: x, y: y)

                    let vBl = values[gridIndex(column, row + 1)]
                    let vBr = values[gridIndex(column + 1, row + 1)]
                    let vTr = values[gridIndex(column + 1, row)]
                    let vTl = values[gridIndex(column, row)]

                    let segments = segmentsForCell(
                        iso: level,
                        corners: [(bl, vBl), (br, vBr), (tr, vTr), (tl, vTl)]
                    )

                    for (a, b) in segments {
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                }
            }
        }

        return path
    }

    private func scalarField(at point: CGPoint) -> CGFloat {
        let t = phase * 0.085
        let sx = point.x * 0.00355
        let sy = point.y * 0.00355

        return
            sin(sx * 1.05 + sy * 0.88 + t) * 0.34 +
            sin(sx * 0.72 - sy * 1.12 - t * 0.72) * 0.30 +
            sin((sx + sy) * 1.25 + t * 0.5) * 0.26 +
            sin(sx * 2.9 + cos(sy * 2.35 + t * 0.35) * 1.1) * 0.22 +
            sin(sx * 0.38) * cos(sy * 0.52 + t * 0.22) * 0.18 +
            sin(sx * 4.2 + sy * 3.1 - t * 0.4) * 0.14 +
            sin(sx * 1.8 - sy * 3.6 + t * 0.28) * 0.12
    }

    private func interpolate(
        iso: CGFloat,
        from a: (CGPoint, CGFloat),
        to b: (CGPoint, CGFloat)
    ) -> CGPoint? {
        if (a.1 >= iso) == (b.1 >= iso) { return nil }
        let t = (iso - a.1) / (b.1 - a.1)
        return CGPoint(
            x: a.0.x + t * (b.0.x - a.0.x),
            y: a.0.y + t * (b.0.y - a.0.y)
        )
    }

    private func segmentsForCell(
        iso: CGFloat,
        corners: [(CGPoint, CGFloat)]
    ) -> [(CGPoint, CGPoint)] {
        let bottom = interpolate(iso: iso, from: corners[0], to: corners[1])
        let right = interpolate(iso: iso, from: corners[1], to: corners[2])
        let top = interpolate(iso: iso, from: corners[2], to: corners[3])
        let left = interpolate(iso: iso, from: corners[3], to: corners[0])

        let above = corners.map { $0.1 >= iso }
        let index =
            (above[0] ? 1 : 0) |
            (above[1] ? 2 : 0) |
            (above[2] ? 4 : 0) |
            (above[3] ? 8 : 0)

        func pair(_ a: CGPoint?, _ b: CGPoint?) -> [(CGPoint, CGPoint)] {
            guard let a, let b else { return [] }
            return [(a, b)]
        }

        let vmid = (corners[0].1 + corners[1].1 + corners[2].1 + corners[3].1) / 4

        switch index {
        case 0, 15: return []
        case 1, 14: return pair(bottom, left)
        case 2, 13: return pair(bottom, right)
        case 3, 12: return pair(right, left)
        case 4, 11: return pair(right, top)
        case 6, 9: return pair(bottom, top)
        case 7, 8: return pair(top, left)
        case 5, 10:
            if vmid >= iso {
                return pair(bottom, left) + pair(right, top)
            } else {
                return pair(bottom, right) + pair(top, left)
            }
        default:
            return []
        }
    }
}

enum ProfileCardImageExport {
    @MainActor
    static func pngData(snapshot: ProfileCardSnapshot, scale: CGFloat = 2) -> Data? {
        let content = ProfileShareCardView(snapshot: snapshot, exportScale: 1)
            .frame(width: 320, height: 480)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return png
    }

    @MainActor
    static func copyImageToPasteboard(snapshot: ProfileCardSnapshot) {
        guard let data = pngData(snapshot: snapshot) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType.png)
    }

    @MainActor
    static func beginSavePanel(snapshot: ProfileCardSnapshot) {
        guard let data = pngData(snapshot: snapshot) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "codebook-profile.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
}
