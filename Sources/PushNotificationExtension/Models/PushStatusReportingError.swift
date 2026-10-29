import Foundation

/// Errors surfaced by the push status reporting API.
public enum PushStatusReportingError: Error, Equatable, LocalizedError, Sendable {

    /// Encoding the push status request failed.
    case requestEncodingFailed(String)

    /// Server response is not a valid HTTP response.
    case invalidHTTPResponse(String)

    /// Network request failed before receiving an HTTP response.
    case requestFailed(String)

    /// Server returned a non-success HTTP status code with optional response messages.
    case httpStatus(Int, [String])

    public var errorDescription: String? {
        switch self {
        case let .requestEncodingFailed(message):
            return PushNotificationLocalization.requestEncodingFailed.format(message)
        case .invalidHTTPResponse(let responseDescription):
            return PushNotificationLocalization.invalidHTTPResponse.format(responseDescription)
        case let .requestFailed(message):
            return PushNotificationLocalization.requestFailed.format(message)
        case let .httpStatus(statusCode, messages):
            let details = messages.joined(separator: " ")
            if details.isEmpty {
                return PushNotificationLocalization.httpStatus.format(statusCode)
            }
            return PushNotificationLocalization.httpStatusWithDetails.format(statusCode, details)
        }
    }
}
