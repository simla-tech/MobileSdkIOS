import Foundation

package enum CoreLocalization: String {
    case customerExternalIDEmpty = "core.error.customer_external_id_empty"
    case crmSiteCodeEmpty = "core.error.crm_site_code_empty"
    case idEmpty = "core.error.customer_id_empty"
    case customerIDNotPositive = "core.error.customer_id_not_positive"
    case customerExternalIDTooLong = "core.error.customer_external_id_too_long"
    case crmSiteCodeTooLong = "core.error.crm_site_code_too_long"
    case keychainInvalidTokenData = "core.error.keychain_invalid_token_data"
    case keychainUnexpectedStatus = "core.error.keychain_unexpected_status"
    case sessionHTTPStatus = "core.error.session_http_status"
    case sessionMissingCredentials = "core.error.session_missing_credentials"
    case requestEncodingFailed = "core.error.request_encoding_failed"
    case responseDecodingFailed = "core.error.response_decoding_failed"
    case requestFailed = "core.error.request_failed"
    case cancelled = "core.error.cancelled"
    case unexpected = "core.error.unexpected"

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
