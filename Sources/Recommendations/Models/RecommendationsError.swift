import Core
import Foundation
import Tracker

/// Errors returned by product recommendation operations.
public enum RecommendationsError: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest(String)
    case missingConnection
    case httpStatus(Int, [String])
    case invalidResponse(String)
    case requestFailed(String)
    case trackingUnavailable
    case consentRequired
    case trackingFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .missingConnection: return RecommendationsLocalization.missingConnection.localized
        case .httpStatus(let code, let messages):
            let details = messages.joined(separator: " ")
            return details.isEmpty
                ? RecommendationsLocalization.httpStatus.format(code)
                : RecommendationsLocalization.httpStatusWithDetails.format(code, details)
        case .invalidResponse(let message):
            return RecommendationsLocalization.invalidResponse.format(message)
        case .requestFailed(let message):
            return RecommendationsLocalization.requestFailed.format(message)
        case .trackingUnavailable:
            return RecommendationsLocalization.trackingUnavailable.localized
        case .consentRequired:
            return RecommendationsLocalization.consentRequired.localized
        case .trackingFailed(let message):
            return RecommendationsLocalization.trackingFailed.format(message)
        case .cancelled:
            return RecommendationsLocalization.cancelled.localized
        }
    }
}

package extension RecommendationsError {
    static func from(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        if let error = error as? TrackerError { return from(error) }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError, error.code == .cancelled { return .cancelled }
        if let error = error as? CoreError {
            switch error {
            case .missingConnectionCredentials: return .missingConnection
            case .httpStatus(let code, let messages): return .httpStatus(code, messages)
            case .responseDecodingFailed(let message): return .invalidResponse(message)
            case .cancelled: return .cancelled
            default: return .requestFailed(error.localizedDescription)
            }
        }
        if error is DecodingError { return .invalidResponse(error.localizedDescription) }
        return .requestFailed(error.localizedDescription)
    }

    static func from(_ error: TrackerError) -> Self {
        switch error {
        case .invalidEvent(let message): return .invalidRequest(message)
        case .consentRequired: return .consentRequired
        case .httpStatus(let status, let messages, _): return .httpStatus(status, messages)
        case .invalidResponse(let message): return .invalidResponse(message)
        case .requestFailed(let message): return .requestFailed(message)
        case .missingConnection: return .missingConnection
        case .unavailable: return .trackingUnavailable
        default: return .trackingFailed(error.localizedDescription)
        }
    }
}
