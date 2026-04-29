import Foundation

enum AIResponseTextExtractor {
    static func extract(from data: Data, provider: InsightsProvider) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return extract(from: json, provider: provider)
    }

    static func extract(from json: [String: Any], provider: InsightsProvider) -> String {
        switch provider.protocolStyle {
        case .openAICompatible:
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = flattenedText(from: message["content"]),
               !content.isEmpty {
                return content
            }

            if let output = json["output"] as? [[String: Any]] {
                let text = output
                    .compactMap { item in flattenedText(from: item["content"]) }
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }

            return ""

        case .anthropicMessages:
            return flattenedText(from: json["content"]) ?? ""
        }
    }

    private static func flattenedText(from payload: Any?) -> String? {
        if let text = payload as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let block = payload as? [String: Any] {
            return flattenedText(from: [block])
        }

        guard let blocks = payload as? [[String: Any]] else { return nil }
        let joined = blocks
            .compactMap(flattenedText(from:))
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func flattenedText(from block: [String: Any]) -> String? {
        if let text = block["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let textObject = block["text"] as? [String: Any],
           let value = textObject["value"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let content = block["content"] {
            return flattenedText(from: content)
        }

        if let value = block["value"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }
}
