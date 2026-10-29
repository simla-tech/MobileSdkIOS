import Foundation

package enum PushLocalization: String {

    case operationSuperseded = "push.error.operation_superseded"
    case authorizationDenied = "push.error.authorization_denied"
    case emptyPushToken = "push.error.empty_push_token"
    case emptyFCMToken = "push.error.empty_fcm_token"
    case emptyFID = "push.error.empty_fid"
    case emptyFirebaseProjectID = "push.error.empty_firebase_project_id"
    case firebaseInstallationIDDisabled = "push.error.firebase_installation_id_disabled"
    case missingCustomerIdentifier = "push.error.missing_customer_identifier"
    case invalidHTTPResponse = "push.error.invalid_http_response"
    case requestEncodingFailed = "push.error.request_encoding_failed"
    case requestFailed = "push.error.request_failed"
    case httpStatus = "push.error.http_status"
    case httpStatusWithDetails = "push.error.http_status_with_details"
    case statusReportingInvalidHTTPResponse = "push.error.status_reporting_invalid_http_response"
    case statusReportingRequestEncodingFailed = "push.error.status_reporting_request_encoding_failed"
    case statusReportingRequestFailed = "push.error.status_reporting_request_failed"
    case statusReportingHTTPStatus = "push.error.status_reporting_http_status"
    case statusReportingHTTPStatusWithDetails = "push.error.status_reporting_http_status_with_details"

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
