/// Current mutable tracker state.
package struct TrackerState: Equatable, Sendable {

    /// retailCRM customer ID used for tracker event attribution.
    package var systemCustomerID: Int64?

    /// External site customer ID used for session and tracker event attribution.
    package var siteCustomerID: String?

    /// Indicates whether tracker events are accepted for the connected site.
    package var isAvailable: Bool

    /// Indicates whether tracker events require explicit consent.
    package var requiresConsent: Bool

    /// User consent state for tracker event collection.
    package var consentState: TrackerConsentState

    package init(
        systemCustomerID: Int64? = nil,
        siteCustomerID: String? = nil,
        isAvailable: Bool = false,
        requiresConsent: Bool = false,
        consentState: TrackerConsentState = .unknown
    ) {
        self.systemCustomerID = systemCustomerID
        self.siteCustomerID = siteCustomerID
        self.isAvailable = isAvailable
        self.requiresConsent = requiresConsent
        self.consentState = consentState
    }
}
