import Foundation

package enum TrackerLocalization: String {
    case clientHTTPStatus = "tracker.error.client_http_status"
    case clientHTTPStatusWithRetry = "tracker.error.client_http_status_with_retry"
    case invalidEvent = "tracker.error.invalid_event"
    case storage = "tracker.error.storage"
    case requestEncodingFailed = "tracker.error.request_encoding_failed"
    case requestFailed = "tracker.error.request_failed"
    case invalidResponse = "tracker.error.invalid_response"
    case eventRejected = "tracker.error.event_rejected"
    case flushIncomplete = "tracker.error.flush_incomplete"
    case serverDetails = "tracker.error.server_details"
    case positiveUInt32 = "tracker.error.positive_uint32"
    case productIdentityRequired = "tracker.error.product_identity_required"
    case customerAttributeRequired = "tracker.error.customer_attribute_required"
    case fieldRequired = "tracker.error.field_required"
    case absoluteURIRequired = "tracker.error.absolute_uri_required"
    case orderSystemIDOutOfRange = "tracker.error.order_system_id_out_of_range"
    case offerSystemIDOutOfRange = "tracker.error.offer_system_id_out_of_range"
    case identifierTooLong = "tracker.error.identifier_too_long"
    case nonNegativeNumber = "tracker.error.non_negative_number"
    case eventTooLarge = "tracker.error.event_too_large"
    case serverRetry = "tracker.error.server_retry"
    case storageUnavailable = "tracker.error.storage_unavailable"
    case missingHTTPResponse = "tracker.error.missing_http_response"
    case storageScopeInactive = "tracker.error.storage_scope_inactive"
    case storageOpenFailed = "tracker.error.storage_open_failed"
    case trackingConsentUnavailable = "tracker.update.tracking_consent_unavailable"
    case queueCapacityExceeded = "tracker.update.queue_capacity_exceeded"
    case sqliteEventPayloadMissing = "tracker.error.sqlite_event_payload_missing"
    case unavailable = "tracker.error.unavailable"
    case consentRequired = "tracker.error.consent_required"
    case missingConnection = "tracker.error.missing_connection"

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
