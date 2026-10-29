import Core
import Foundation

/// Errors surfaced by the Tracker module.
public enum TrackerError: Error, Equatable, LocalizedError, Sendable {
    /// Event parameters cannot be converted into a valid tracker event.
    case invalidEvent(String)
    /// The SDK rejected the single-event JSON request before sending it.
    case eventTooLarge(sizeBytes: Int, limitBytes: Int)
    /// The tracker cannot currently accept events.
    case unavailable
    /// The site requires tracking consent before events can be queued.
    case consentRequired
    /// Tracker session credentials are unavailable.
    case missingConnection
    /// Reading or writing the local event queue failed.
    case storage(String)
    /// Encoding the outgoing request failed.
    case requestEncodingFailed(String)
    /// Sending the outgoing request failed.
    case requestFailed(String)
    /// The collector returned an unreadable response.
    case invalidResponse(String)
    /// The collector returned a non-success HTTP status and optional retry delay.
    case httpStatus(Int, [String], retryAfter: TimeInterval?)
    /// The collector rejected one event.
    case eventRejected(String)
    /// IDs not marked as delivered during `flushAll`, including locally oversized events.
    case flushIncomplete([String])

    /// Localized summary of the error, including available diagnostic details.
    public var errorDescription: String? {
        switch self {
        case let .invalidEvent(message):
            return TrackerLocalization.invalidEvent.format(message)
        case let .eventTooLarge(sizeBytes, limitBytes):
            return TrackerLocalization.eventTooLarge.format(Int64(sizeBytes), Int64(limitBytes))
        case let .storage(message):
            return TrackerLocalization.storage.format(message)
        case let .requestEncodingFailed(message):
            return TrackerLocalization.requestEncodingFailed.format(message)
        case let .requestFailed(message):
            return TrackerLocalization.requestFailed.format(message)
        case let .invalidResponse(message):
            return TrackerLocalization.invalidResponse.format(message)
        case let .eventRejected(message):
            return TrackerLocalization.eventRejected.format(message)
        case let .flushIncomplete(eventIDs):
            return TrackerLocalization.flushIncomplete.format(eventIDs.count)
        case .unavailable:
            return TrackerLocalization.unavailable.localized
        case .consentRequired:
            return TrackerLocalization.consentRequired.localized
        case .missingConnection:
            return TrackerLocalization.missingConnection.localized
        case let .httpStatus(status, messages, retryAfter):
            let summary = retryAfter.map {
                TrackerLocalization.clientHTTPStatusWithRetry.format(status, $0)
            } ?? TrackerLocalization.clientHTTPStatus.format(status)
            guard !messages.isEmpty else { return summary }
            return summary + " " + TrackerLocalization.serverDetails.format(messages.joined(separator: " "))
        }
    }
}

package extension TrackerError {
    static func from(_ error: Error) -> TrackerError {
        if let error = error as? TrackerError { return error }
        if let error = error as? CoreError {
            switch error {
            case .missingConnectionCredentials: return .missingConnection
            case let .httpStatus(status, messages): return .httpStatus(status, messages, retryAfter: nil)
            case let .responseDecodingFailed(message): return .invalidResponse(message)
            case let .requestEncodingFailed(message): return .requestEncodingFailed(message)
            default: return .requestFailed(error.localizedDescription)
            }
        }
        if error is DecodingError { return .invalidResponse(error.localizedDescription) }
        return .requestFailed(error.localizedDescription)
    }
}
