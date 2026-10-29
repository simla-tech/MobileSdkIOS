import Core
import Foundation

package struct TrackerStoreEventsResponse: Decodable, Equatable, Sendable {
    package let eventErrors: [String: [String: String]]
    package let topLevelError: String?

    package init(eventErrors: [String: [String: String]] = [:], topLevelError: String? = nil) {
        self.eventErrors = eventErrors
        self.topLevelError = topLevelError
    }

    package func failures(attemptedEventIDs: Set<String>) -> TrackerEventFailures {
        TrackerEventFailures(
            response: self,
            attemptedEventIDs: attemptedEventIDs
        )
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let topLevel = try? container.decode(TopLevelError.self) {
            self.eventErrors = [:]
            self.topLevelError = topLevel.error
            return
        }

        self.eventErrors = try container.decode([String: [String: String]].self)
        self.topLevelError = nil
    }

    private struct TopLevelError: Decodable {
        let error: String
    }
}

package struct TrackerEventFailures: Equatable, Sendable {
    package let retryableIDs: Set<String>
    package let rejectedReasons: [String: String]

    package init(
        retryableIDs: Set<String> = [],
        rejectedReasons: [String: String] = [:]
    ) {
        self.retryableIDs = retryableIDs
        self.rejectedReasons = rejectedReasons
    }

    package init(
        response: TrackerStoreEventsResponse,
        attemptedEventIDs: Set<String>
    ) {

        let tryAgainLater = "try again later"

        if let topLevelError = response.topLevelError?.nilIfEmpty {
            if topLevelError.lowercased() == tryAgainLater {
                self.init(retryableIDs: attemptedEventIDs)
            } else {
                self.init(
                    rejectedReasons: Dictionary(uniqueKeysWithValues: attemptedEventIDs.map { ($0, topLevelError) })
                )
            }
            return
        }

        var retryableIDs = Set<String>()
        var rejectedReasons: [String: String] = [:]

        for (eventID, errors) in response.eventErrors where attemptedEventIDs.contains(eventID) {
            let normalizedErrors = errors
                .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.value.isEmpty }
            let hasRetryableError = normalizedErrors.values.contains {
                $0.lowercased() == tryAgainLater
            }

            if hasRetryableError {
                retryableIDs.insert(eventID)
            } else if !normalizedErrors.isEmpty {
                rejectedReasons[eventID] = normalizedErrors
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: ", ")
            }
        }

        self.init(
            retryableIDs: retryableIDs,
            rejectedReasons: rejectedReasons
        )
    }
}
