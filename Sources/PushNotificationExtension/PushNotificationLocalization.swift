import Foundation

package enum PushNotificationLocalization: String {
    case httpStatus = "push_status.error.http_status"
    case httpStatusWithDetails = "push_status.error.http_status_with_details"
    case invalidHTTPResponse = "push_status.error.invalid_http_response"
    case requestEncodingFailed = "push_status.error.request_encoding_failed"
    case requestFailed = "push_status.error.request_failed"

    package var localized: String {
        NSLocalizedString(
            rawValue,
            bundle: .module,
            comment: ""
        )
    }

    package func format(_ arguments: CVarArg...) -> String {
        String(format: localized, arguments: arguments)
    }
}
