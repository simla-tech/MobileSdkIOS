import Foundation

/// Formats backend message timestamps for message metadata UI.
package enum MessageMetadataFormatter {

    /// Returns the display timestamp for a consultant message.
    package static func metadataText(for message: ConsultantMessage) -> String? {
        formattedTime(from: message.time)
    }

    /// Parses a backend timestamp string and returns `HH:mm` display text.
    private static func formattedTime(from value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        guard let date = DateParser.date(from: value) else {
            return fallbackTime(from: value)
        }

        return timeFormatter.string(from: date)
    }

    /// Extracts `HH:mm` directly from timestamp-like strings when parsing fails.
    private static func fallbackTime(from value: String) -> String? {
        guard
            let timeStart = value.firstIndex(of: "T"),
            value.distance(from: timeStart, to: value.endIndex) >= 6
        else {
            return nil
        }

        let start = value.index(after: timeStart)
        let end = value.index(start, offsetBy: 5)
        return String(value[start..<end])
    }

    /// Output formatter for message metadata time labels.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
