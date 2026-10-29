//
//  OnlineConsultantDateParser.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

import Foundation

package enum DateParser {

    /// Parses backend timestamps that may use several RFC3339/ISO8601 precisions.
    package static func date(from value: String) -> Date? {
        isoDateFormatter.date(from: value)
        ?? fallbackISODateFormatter.date(from: value)
        ?? rfc3339MicrosecondsFormatter.date(from: value)
        ?? rfc3339MillisecondsFormatter.date(from: value)
    }

    package static func string(from value: Date) -> String {
        isoDateFormatter.string(from: value)
    }

    /// ISO8601 parser for timestamps with fractional seconds.
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 parser for timestamps without fractional seconds.
    private static let fallbackISODateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// RFC3339 parser for Go/backend timestamps with microsecond precision.
    private static let rfc3339MicrosecondsFormatter: DateFormatter = {
        makeInputDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    }()

    /// RFC3339 parser for timestamps with millisecond precision.
    private static let rfc3339MillisecondsFormatter: DateFormatter = {
        makeInputDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    }()

    /// Creates a stable POSIX date formatter for backend timestamp parsing.
    private static func makeInputDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
