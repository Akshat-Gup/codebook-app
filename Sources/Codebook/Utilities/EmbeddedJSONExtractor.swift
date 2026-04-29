import Foundation

enum EmbeddedJSONExtractor {
    static func extractObjectText(from text: String) -> String {
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards)
        else {
            return text
        }

        return String(text[start.lowerBound..<end.upperBound])
    }
}
