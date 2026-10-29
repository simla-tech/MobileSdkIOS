import Foundation

package enum RecommendationsLocalization: String {
    case httpStatus = "recommendations.error.http_status"
    case httpStatusWithDetails = "recommendations.error.http_status_with_details"
    case mechanicCodeEmpty = "recommendations.error.mechanic_code_empty"
    case missingConnection = "recommendations.error.missing_connection"
    case offerContextConflict = "recommendations.error.offer_context_conflict"
    case offerIDInvalid = "recommendations.error.offer_id_invalid"
    case productAndOfferConflict = "recommendations.error.product_and_offer_conflict"
    case productContextConflict = "recommendations.error.product_context_conflict"
    case productIDInvalid = "recommendations.error.product_id_invalid"
    case requestFailed = "recommendations.error.request_failed"
    case blockCodeEmpty = "recommendations.error.block_code_empty"
    case invalidResponse = "recommendations.error.invalid_response"
    case trackingUnavailable = "recommendations.error.tracking_unavailable"
    case consentRequired = "recommendations.error.consent_required"
    case trackingFailed = "recommendations.error.tracking_failed"
    case cancelled = "recommendations.error.cancelled"
    case executionIDInvalid = "recommendations.error.execution_id_invalid"
    case clickProductIDInvalid = "recommendations.error.click_product_id_invalid"
    case positionInvalid = "recommendations.error.position_invalid"
    case screenURIInvalid = "recommendations.error.screen_uri_invalid"

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
