import AppKit
import SwiftUI

/// Vertical strip that shows `resizeLeftRight` for `HSplitView` dividers without stealing clicks or drags
/// from the divider, scrollers, or other views beneath it.
private final class PassThroughResizeCursorNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard bounds.width > 0, bounds.height > 0 else { return }
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}

private struct PassThroughResizeCursorStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PassThroughResizeCursorNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Use on the left pane beside a vertical split divider (e.g. sidebar or list column).
    func hSplitPaneTrailingResizeCursorStrip(width: CGFloat = 6) -> some View {
        overlay(alignment: .trailing) {
            PassThroughResizeCursorStrip()
                .frame(width: width)
        }
    }

    /// Use on the right pane beside a vertical split divider (e.g. detail column).
    func hSplitPaneLeadingResizeCursorStrip(width: CGFloat = 6) -> some View {
        overlay(alignment: .leading) {
            PassThroughResizeCursorStrip()
                .frame(width: width)
        }
    }
}
