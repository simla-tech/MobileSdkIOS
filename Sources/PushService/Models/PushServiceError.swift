import Foundation

/// Errors surfaced by push core.
public enum PushServiceError: Error, Equatable, LocalizedError, Sendable {

    /// Reasons why a notification status could not be reported.
    public enum StatusReportingFailure: Equatable, Sendable {
        /// The status request could not be encoded.
        case requestEncodingFailed(String)
        /// The response was not a valid HTTP response.
        case invalidHTTPResponse(String)
        /// The request failed before an HTTP response was received.
        case requestFailed(String)
        /// The server returned an HTTP status and optional messages.
        case httpStatus(Int, [String])
    }

    /// Reading or writing the local push registration database failed.
    case storage(String)

    /// A newer category list replaced a pending registration before it could start.
    case operationSuperseded

    /// The customer identity is invalid.
    case invalidCustomerIdentity(String)

    /// The user denied authorization to display notifications.
    case authorizationDenied

    /// A push identifier is not yet available.
    case emptyPushToken

    /// FCM token is empty after trimming whitespace.
    case emptyFCMToken

    /// Firebase installation ID is empty after trimming whitespace.
    case emptyFID

    /// Firebase project ID is unavailable from configured Firebase options.
    case emptyFirebaseProjectID

    /// Firebase Messaging installation ID delivery is disabled in app configuration.
    case firebaseInstallationIDDisabled

    /// Customer ID or external customer ID is missing.
    case missingCustomerIdentifier

    /// Server response is not a valid HTTP response.
    case invalidHTTPResponse(String)

    /// Encoding the push token registration request failed.
    case requestEncodingFailed(String)

    /// Network request failed before receiving an HTTP response.
    case requestFailed(String)

    /// Server returned a non-success HTTP status code with optional response messages.
    case httpStatus(Int, [String])

    /// Reporting a notification status to the backend failed.
    case statusReporting(StatusReportingFailure)

    /// Firebase Messaging registration or FCM token retrieval failed.
    case firebaseMessaging(Error)

    /// Firebase Installations failed to provide an installation ID.
    case firebaseInstallations(Error)

    /// Localized human-readable error description.
    public var errorDescription: String? {
        switch self {
        case .operationSuperseded:
            return PushLocalization.operationSuperseded.localized
        case .storage(let message), .invalidCustomerIdentity(let message):
            return message
        case .authorizationDenied:
            return PushLocalization.authorizationDenied.localized
        case .emptyPushToken:
            return PushLocalization.emptyPushToken.localized
        case .emptyFCMToken:
            return PushLocalization.emptyFCMToken.localized
        case .emptyFID:
            return PushLocalization.emptyFID.localized
        case let .firebaseMessaging(error):
            return error.localizedDescription
        case let .firebaseInstallations(error):
            return error.localizedDescription
        case .emptyFirebaseProjectID:
            return PushLocalization.emptyFirebaseProjectID.localized
        case .firebaseInstallationIDDisabled:
            return PushLocalization.firebaseInstallationIDDisabled.localized
        case .missingCustomerIdentifier:
            return PushLocalization.missingCustomerIdentifier.localized
        case .invalidHTTPResponse(let responseDescription):
            return PushLocalization.invalidHTTPResponse.format(responseDescription)
        case let .requestEncodingFailed(message):
            return PushLocalization.requestEncodingFailed.format(message)
        case let .requestFailed(message):
            return PushLocalization.requestFailed.format(message)
        case let .httpStatus(statusCode, messages):
            let details = messages.joined(separator: " ")
            if details.isEmpty {
                return PushLocalization.httpStatus.format(statusCode)
            }
            return PushLocalization.httpStatusWithDetails.format(statusCode, details)
        case let .statusReporting(reason):
            switch reason {
            case let .requestEncodingFailed(message):
                return PushLocalization.statusReportingRequestEncodingFailed.format(message)
            case let .invalidHTTPResponse(responseDescription):
                return PushLocalization.statusReportingInvalidHTTPResponse.format(responseDescription)
            case let .requestFailed(message):
                return PushLocalization.statusReportingRequestFailed.format(message)
            case let .httpStatus(statusCode, messages):
                let details = messages.joined(separator: " ")
                if details.isEmpty {
                    return PushLocalization.statusReportingHTTPStatus.format(statusCode)
                }
                return PushLocalization.statusReportingHTTPStatusWithDetails.format(statusCode, details)
            }
        }
    }

    /// Compares push service errors, including their associated values.
    ///
    /// - Parameters:
    ///   - lhs: First error to compare.
    ///   - rhs: Second error to compare.
    public static func == (lhs: PushServiceError, rhs: PushServiceError) -> Bool {
        switch (lhs, rhs) {
        case let (.storage(left), .storage(right)),
             let (.invalidCustomerIdentity(left), .invalidCustomerIdentity(right)),
             let (.invalidHTTPResponse(left), .invalidHTTPResponse(right)),
             let (.requestEncodingFailed(left), .requestEncodingFailed(right)),
             let (.requestFailed(left), .requestFailed(right)):
            return left == right
        case let (.httpStatus(leftCode, leftMessages), .httpStatus(rightCode, rightMessages)):
            return leftCode == rightCode && leftMessages == rightMessages
        case let (.statusReporting(left), .statusReporting(right)):
            return left == right
        case let (.firebaseMessaging(left), .firebaseMessaging(right)),
             let (.firebaseInstallations(left), .firebaseInstallations(right)):
            return (left as NSError) == (right as NSError)
        case (.operationSuperseded, .operationSuperseded),
             (.authorizationDenied, .authorizationDenied),
             (.emptyPushToken, .emptyPushToken),
             (.emptyFCMToken, .emptyFCMToken),
             (.emptyFID, .emptyFID),
             (.emptyFirebaseProjectID, .emptyFirebaseProjectID),
             (.firebaseInstallationIDDisabled, .firebaseInstallationIDDisabled),
             (.missingCustomerIdentifier, .missingCustomerIdentifier):
            return true
        default:
            return false
        }
    }
}
