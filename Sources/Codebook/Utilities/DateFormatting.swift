import Foundation

enum DateFormatting {
    private static func formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    static func parse(_ string: String) -> Date? {
        formatter(withFractionalSeconds: true).date(from: string) ?? formatter(withFractionalSeconds: false).date(from: string)
    }

    static func displayString(from date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
