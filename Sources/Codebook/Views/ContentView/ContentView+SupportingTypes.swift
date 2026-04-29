import SwiftUI

// MARK: - Supporting Types

struct ProviderShareItem: Identifiable {
    var id: String { provider.rawValue }
    let provider: IntegrationProvider
}

struct ProviderMiniChartData: Identifiable {
    var id: IntegrationProvider { provider }
    let provider: IntegrationProvider
    let total: Int
    let prompts: [ImportedPrompt]
    let estimatedCostSummary: PromptCostSummary
    /// Last `ProviderCardHeatmap.historyDayCount` days for panning + heatmap.
    let historyStats: [DailyPromptStat]
}

struct AppKitSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let focusRequestID: Int
    let onTextChange: () -> Void
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onTextChange: onTextChange, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.focusRingType = .none
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSubmit = onSubmit

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)
                nsView.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        var onTextChange: () -> Void
        var onSubmit: (() -> Void)?
        var lastFocusRequestID: Int

        init(text: Binding<String>, isFocused: Binding<Bool>, onTextChange: @escaping () -> Void, onSubmit: (() -> Void)?) {
            self.text = text
            self.isFocused = isFocused
            self.onTextChange = onTextChange
            self.onSubmit = onSubmit
            self.lastFocusRequestID = 0
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
            onTextChange()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

struct ProviderStat: Identifiable {
    let id: String
    let name: String
    let count: Int
}

struct DailyCommitStat: Hashable {
    let sha: String
    let message: String?
}

struct DailyPromptStat: Identifiable {
    let id: Date
    let day: Date
    let count: Int
    let commits: [DailyCommitStat]
}

struct DashboardMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let trailingValue: String?
    let subtitle: String?
}
