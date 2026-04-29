import AppKit
import SwiftUI

/// Inferred LLM vendor from `ImportedPrompt.modelID` (distinct from `IntegrationProvider` / IDE source).
enum ModelVendor: String, Hashable, Sendable {
    case openAI
    case anthropic
    case google
    case meta
    case mistral
    case xAI
    case amazon
    case cohere
    case other

    static func detect(modelID: String?) -> ModelVendor? {
        guard let raw = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return nil
        }

        if raw.contains("claude") { return .anthropic }
        if raw.contains("gpt")
            || raw.contains("o1")
            || raw.contains("o3")
            || raw.contains("o4")
            || raw.contains("davinci")
            || raw.contains("text-davinci")
            || raw.contains("chatgpt") { return .openAI }
        if raw.contains("gemini") || raw.contains("palm") { return .google }
        if raw.contains("llama") || raw.contains("meta-llama") { return .meta }
        if raw.contains("mistral") || codestralLike(raw) { return .mistral }
        if raw.contains("grok") { return .xAI }
        if raw.contains("bedrock") || raw.contains("anthropic.claude") || raw.contains("amazon") { return .amazon }
        if raw.contains("command") || raw.contains("cohere") { return .cohere }

        if raw.contains("local") || raw.contains("unknown") || raw == "default" {
            return nil
        }
        return .other
    }

    private static func codestralLike(_ raw: String) -> Bool {
        raw.contains("codestral") || raw.contains("mistral-")
    }

    /// When true the icon asset is rendered with its original colours (not tinted to the primary colour).
    fileprivate var usesColorRendering: Bool {
        switch self {
        case .google: return true
        default: return false
        }
    }

    fileprivate var assetName: String? {
        switch self {
        case .openAI:
            return "openai"
        case .anthropic:
            return "anthropic"
        case .google:
            return "google"
        case .meta:
            return "meta"
        case .mistral:
            return "mistral"
        case .xAI:
            return "xai"
        case .amazon:
            return "amazon"
        case .cohere:
            return "cohere"
        case .other:
            return nil
        }
    }

    fileprivate var fallbackSystemImage: String {
        switch self {
        case .openAI: return "circle.hexagongrid.fill"
        case .anthropic: return "sparkles"
        case .google: return "diamond.fill"
        case .meta: return "infinity"
        case .mistral: return "wind"
        case .xAI: return "xmark"
        case .amazon: return "cube.transparent.fill"
        case .cohere: return "triangle.fill"
        case .other: return "cpu"
        }
    }
}

struct ModelVendorIconView: View {
    let vendor: ModelVendor
    var size: CGFloat = 11

    var body: some View {
        Group {
            if vendor == .anthropic {
                PlatformIconView(provider: .claude, size: size)
            } else if let image = ModelVendorIconStore.image(for: vendor, size: size) {
                if vendor.usesColorRendering {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .renderingMode(.original)
                } else {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .renderingMode(.template)
                        .foregroundStyle(Color.primary)
                }
            } else {
                Image(systemName: vendor.fallbackSystemImage)
                    .font(.system(size: size - 1, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
private enum ModelVendorIconStore {
    private static var cache: [String: NSImage] = [:]
    private static let resourceBundleName = "Codebook_Codebook.bundle"

    static func image(for vendor: ModelVendor, size: CGFloat) -> NSImage? {
        guard let assetName = vendor.assetName else { return nil }

        let cacheKey = "\(assetName)-\(Int(size.rounded()))"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let url = resourceBundle?.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "model-vendor-icons"
        ), let image = NSImage(contentsOf: url),
           let rendered = renderedImage(source: image, size: size, isTemplate: !vendor.usesColorRendering) else {
            return nil
        }

        cache[cacheKey] = rendered
        return rendered
    }

    private static var resourceBundle: Bundle? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(resourceBundleName)"),
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName)
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        RuntimeLogger.shared.error("Unable to load \(resourceBundleName) from app bundle")
        return nil
    }

    private static func renderedImage(source: NSImage, size: CGFloat, isTemplate: Bool = true) -> NSImage? {
        let canvasSize = NSSize(width: size, height: size)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: canvasSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.isTemplate = isTemplate
        return image
    }
}
