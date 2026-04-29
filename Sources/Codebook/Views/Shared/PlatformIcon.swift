import AppKit
import SwiftUI

struct PlatformIconView: View {
    let provider: IntegrationProvider
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let image = PlatformIconStore.image(for: provider, size: size) {
                Image(nsImage: image)
                    .interpolation(.high)
                    // Bitmap assets from SVG or dark app marks are often black/near-black; without
                    // template rendering they stay black on dark backgrounds (looks "broken").
                    .renderingMode(tintsWithForegroundStyle ? .template : .original)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size - 1, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    /// Copilot's SVG-derived bitmap is monochrome and needs template tinting for dark mode.
    private var tintsWithForegroundStyle: Bool {
        switch provider {
        case .copilot:
            true
        case .codex:
            true
        case .claude, .cursor, .opencode, .antigravity:
            false
        }
    }

    private var fallbackSystemImage: String {
        switch provider {
        case .codex:
            return "circle.hexagongrid.fill"
        case .claude:
            return "sparkles"
        case .cursor:
            return "cursorarrow"
        case .copilot:
            return "chevron.left.forwardslash.chevron.right"
        case .opencode:
            return "curlybraces"
        case .antigravity:
            return "sparkle.2"
        }
    }
}

struct AllPlatformsIconView: View {
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: size, weight: .medium))
            .frame(width: size, height: size)
    }
}

@MainActor
private enum PlatformIconStore {
    private static var cache: [String: NSImage] = [:]
    private static let resourceBundleName = "Codebook_Codebook.bundle"

    static func image(for provider: IntegrationProvider, size: CGFloat) -> NSImage? {
        let cacheKey = "\(provider.rawValue)-\(Int(size.rounded()))"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let url = resourceBundle?.url(
            forResource: provider.rawValue,
            withExtension: "png",
            subdirectory: "platform-icons"
        ), let image = NSImage(contentsOf: url),
           let rendered = renderedImage(for: provider, source: image, size: size) else {
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

    private static func renderedImage(for provider: IntegrationProvider, source: NSImage, size: CGFloat) -> NSImage? {
        let canvasSize = NSSize(width: size, height: size)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        let inset = max(0, size * 0.06)
        let drawRect = canvasRect.insetBy(dx: inset, dy: inset)

        if provider == .cursor || provider == .copilot || provider == .opencode || provider == .antigravity {
            let clipPath = NSBezierPath(roundedRect: drawRect, xRadius: size * 0.24, yRadius: size * 0.24)
            clipPath.addClip()
        }

        source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        return image
    }
}
