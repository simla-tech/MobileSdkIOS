import Foundation

package enum TrackerRateLimit {

    package static func retryAfter(
        from response: HTTPURLResponse,
        data: Data
    ) -> TimeInterval? {
        retryAfter(fromHeader: response.value(forHTTPHeaderField: "Retry-After"))
            ?? retryAfter(fromBody: data)
    }

    private static func retryAfter(fromHeader value: String?) -> TimeInterval? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(trimmed) {
            return max(seconds, 0)
        }

        guard let date = makeHTTPDateFormatter().date(from: trimmed) else {
            return nil
        }

        return max(date.timeIntervalSinceNow, 0)
    }

    private static func retryAfter(fromBody data: Data) -> TimeInterval? {
        guard
            !data.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return retryAfterMilliseconds(object["retry_after_ms"])
            ?? retryAfterMilliseconds(object["retry-after"])
    }

    private static func retryAfterMilliseconds(_ value: Any?) -> TimeInterval? {
        let milliseconds: Double?
        switch value {
        case let value as NSNumber:
            milliseconds = value.doubleValue
        case let value as String:
            milliseconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            milliseconds = nil
        }

        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }

        return milliseconds / 1_000
    }

    private static func makeHTTPDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }
}
