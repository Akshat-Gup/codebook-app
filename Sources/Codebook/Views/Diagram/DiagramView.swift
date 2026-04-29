import SwiftUI
import WebKit

// MARK: - Diagram Kind

enum DiagramKind: Hashable {
    case overview
    case components
    case dataFlow
    case dependencies
    case entryPoints
    case patterns
    case layers
    case feature(String)

    var title: String {
        switch self {
        case .overview:         return "Overview"
        case .components:       return "Components"
        case .dataFlow:         return "Data Flow"
        case .dependencies:     return "Dependencies"
        case .entryPoints:      return "Entry Points"
        case .patterns:         return "Patterns"
        case .layers:           return "Layers"
        case .feature(let n):   return n
        }
    }

    var systemImage: String {
        switch self {
        case .overview:         return "rectangle.3.group.bubble"
        case .components:       return "square.stack.3d.up"
        case .dataFlow:         return "arrow.triangle.swap"
        case .dependencies:     return "link"
        case .entryPoints:      return "arrow.right.to.line"
        case .patterns:         return "puzzlepiece"
        case .layers:           return "rectangle.3.group"
        case .feature:          return "sparkle"
        }
    }

    /// All predefined diagram types shown as quick-generate chips.
    static let predefined: [DiagramKind] = [
        .overview, .components, .dataFlow, .dependencies, .entryPoints, .patterns, .layers
    ]
}

extension DiagramKind: Codable {
    private enum CodingKeys: String, CodingKey { case kind, featureName }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .overview:             try container.encode("overview",     forKey: .kind)
        case .components:           try container.encode("components",   forKey: .kind)
        case .dataFlow:             try container.encode("dataFlow",     forKey: .kind)
        case .dependencies:         try container.encode("dependencies", forKey: .kind)
        case .entryPoints:          try container.encode("entryPoints",  forKey: .kind)
        case .patterns:             try container.encode("patterns",     forKey: .kind)
        case .layers:               try container.encode("layers",       forKey: .kind)
        case .feature(let name):
            try container.encode("feature", forKey: .kind)
            try container.encode(name,      forKey: .featureName)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "overview":        self = .overview
        case "components":      self = .components
        case "dataFlow":        self = .dataFlow
        case "dependencies":    self = .dependencies
        case "entryPoints":     self = .entryPoints
        case "patterns":        self = .patterns
        case "layers":          self = .layers
        case "feature":
            let name = try container.decode(String.self, forKey: .featureName)
            self = .feature(name)
        default: self = .overview
        }
    }
}

// MARK: - Saved Diagram

struct SavedDiagram: Identifiable, Codable {
    let id: String
    let projectID: String
    let kind: DiagramKind
    var svgContent: String
    let createdAt: Date

    var title: String      { kind.title }
    var systemImage: String { kind.systemImage }

    init(projectID: String, kind: DiagramKind, svgContent: String) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.kind = kind
        self.svgContent = svgContent
        self.createdAt = .now
    }
}

// MARK: - SVG Web View

struct SVGWebView: NSViewRepresentable {
    let svgContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "javaScriptEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadSVG(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadSVG(into: webView)
    }

    private func loadSVG(into webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { width: 100%; height: 100%; overflow: auto; background: transparent; }
            body {
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
                padding: 16px;
            }
            svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(svgContent)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Diagram Tab Chip

private struct DiagramTabChip: View {
    let diagram: SavedDiagram
    let isSelected: Bool
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isUpdating {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: diagram.systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(diagram.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
                .overlay {
                    if !isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Quick Generate Chip

private struct QuickGenerateChip: View {
    let kind: DiagramKind
    let exists: Bool
    let isGenerating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 11, height: 11)
                } else if exists {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(kind.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(exists ? Color.accentColor : Color.primary.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(exists ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                exists ? Color.accentColor.opacity(0.2) : Color(nsColor: .separatorColor),
                                lineWidth: 0.5
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diagram Sheet

struct DiagramSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDiagramID: String?
    @State private var featureText = ""
    @FocusState private var featureFieldFocused: Bool

    private var projectID: String? { model.selectedProjectSummary?.id }

    private var projectDiagrams: [SavedDiagram] {
        guard let pid = projectID else { return [] }
        return model.savedDiagrams
            .filter { $0.projectID == pid }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var selectedDiagram: SavedDiagram? {
        guard let id = selectedDiagramID else { return projectDiagrams.last }
        return projectDiagrams.first(where: { $0.id == id }) ?? projectDiagrams.last
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !projectDiagrams.isEmpty || model.diagramIsGenerating {
                tabStrip
                Divider()
            }
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            generationBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if projectDiagrams.isEmpty && !model.diagramIsGenerating {
                model.generateDiagram(kind: .overview)
            } else {
                selectedDiagramID = projectDiagrams.last?.id
            }
        }
        .onChange(of: model.diagramLastAddedID) { _, newID in
            guard let newID else { return }
            if projectDiagrams.contains(where: { $0.id == newID }) {
                selectedDiagramID = newID
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            CardSectionIcon(systemName: "rectangle.3.group.bubble")
            Text("Diagrams")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(20)
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(projectDiagrams) { diagram in
                    DiagramTabChip(
                        diagram: diagram,
                        isSelected: selectedDiagram?.id == diagram.id,
                        isUpdating: model.diagramUpdatingID == diagram.id
                    )
                    .onTapGesture { selectedDiagramID = diagram.id }
                }
                // Pending chip while a new (non-update) generation is in progress
                if model.diagramIsGenerating && model.diagramUpdatingID == nil {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                        Text(model.diagramGeneratingKind.map { "Generating \($0.title)…" } ?? "Generating…")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if model.diagramIsGenerating && projectDiagrams.isEmpty {
            generatingView
        } else if let diagram = selectedDiagram {
            ZStack(alignment: .topTrailing) {
                SVGWebView(svgContent: diagram.svgContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Action buttons overlay
                HStack(spacing: 6) {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(diagram.svgContent, forType: .string)
                    } label: {
                        Label("Copy SVG", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        model.updateDiagram(id: diagram.id)
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.diagramIsGenerating)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 12)
                .padding(.trailing, 24)

                // Dimming overlay while this specific diagram is being regenerated
                if model.diagramUpdatingID == diagram.id {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor).opacity(0.75)
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.regular)
                            Text("Updating diagram…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        } else if let error = model.diagramError {
            errorView(error)
        } else {
            generatingView
        }
    }

    private var generatingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.regular)
            Text("Scanning codebase and generating diagram…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Generate Overview") {
                model.generateDiagram(kind: .overview)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Generation Bar

    private var generationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick-generate chips for predefined diagram types
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DiagramKind.predefined, id: \.title) { kind in
                        let existingDiagram = projectDiagrams.first(where: { $0.kind == kind })
                        let isGeneratingThis = model.diagramIsGenerating
                            && model.diagramGeneratingKind == kind
                            && model.diagramUpdatingID == nil
                        QuickGenerateChip(
                            kind: kind,
                            exists: existingDiagram != nil,
                            isGenerating: isGeneratingThis
                        ) {
                            if let existing = existingDiagram {
                                selectedDiagramID = existing.id
                            } else {
                                model.generateDiagram(kind: kind)
                            }
                        }
                        .disabled(model.diagramIsGenerating)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Feature diagram text field
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                TextField("Diagram a specific feature…", text: $featureText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($featureFieldFocused)
                    .onSubmit { submitFeature() }

                Button { submitFeature() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            featureText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AnyShapeStyle(.tertiary)
                                : AnyShapeStyle(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(featureText.trimmingCharacters(in: .whitespaces).isEmpty || model.diagramIsGenerating)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func submitFeature() {
        let trimmed = featureText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        featureText = ""
        model.generateDiagram(kind: .feature(trimmed))
    }

}


