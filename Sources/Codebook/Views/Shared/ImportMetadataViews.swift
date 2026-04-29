import SwiftUI

// MARK: - Imported metadata token summary

struct ImportMetadataTokenSummary: View {
    let prompt: ImportedPrompt
    let total: Int
    let formatTokenCount: (Int) -> String

    @State private var breakdownExpanded = false

    private var hasBreakdown: Bool {
        prompt.inputTokens != nil
            || (prompt.cachedInputTokens ?? 0) > 0
            || prompt.outputTokens != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if hasBreakdown {
                    Button {
                        breakdownExpanded.toggle()
                    } label: {
                        pillLabel(showsChevron: true, chevronDown: breakdownExpanded)
                    }
                    .buttonStyle(.plain)
                } else {
                    pillLabel(showsChevron: false, chevronDown: false)
                }
            }

            if breakdownExpanded && hasBreakdown {
                VStack(alignment: .leading, spacing: 3) {
                    if let input = prompt.inputTokens {
                        tokenBreakdownLine(title: "Input", value: formatTokenCount(input))
                    }
                    if let cached = prompt.cachedInputTokens, cached > 0 {
                        tokenBreakdownLine(title: "Cached input", value: formatTokenCount(cached))
                    }
                    if let output = prompt.outputTokens {
                        tokenBreakdownLine(title: "Output", value: formatTokenCount(output))
                    }
                }
                .textSelection(.enabled)
                .padding(.leading, 4)
            }
        }
    }

    private func pillLabel(showsChevron: Bool, chevronDown: Bool) -> some View {
        HStack(spacing: 5) {
            if showsChevron {
                Image(systemName: chevronDown ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(formatTokenCount(total)) tokens")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func tokenBreakdownLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
