import Foundation

/// Identifies an integrator's customer in a retailCRM store.
public struct CrmSdkCustomerIdentity: Equatable, Sendable {
    public let customerId: Int64?
    public let siteCustomerId: String?
    public let siteCode: String?

    /// Creates a retailCRM customer identity for the shared SDK session.
    ///
    /// - Parameters:
    ///   - customerId: Internal retailCRM customer ID, if known.
    ///   - siteCustomerId: External retailCRM customer ID, if known.
    ///   - siteCode: CRM site code required with an external customer ID.
    public init(
        customerId: Int64? = nil,
        siteCustomerId: String? = nil,
        siteCode: String? = nil
    ) {
        self.customerId = customerId
        self.siteCustomerId = siteCustomerId?.nilIfEmpty
        self.siteCode = siteCode?.nilIfEmpty
    }

    package func validated() throws -> CrmSdkCustomerIdentity {
        guard customerId != nil || siteCustomerId != nil else {
            throw CoreError.invalidCustomerIdentity(
                CoreLocalization.idEmpty.localized
            )
        }

        if let customerId, customerId <= 0 {
            throw CoreError.invalidCustomerIdentity(
                CoreLocalization.customerIDNotPositive.localized
            )
        }

        if let siteCustomerId, siteCustomerId.unicodeScalars.count > 255 {
            throw CoreError.invalidCustomerIdentity(
                CoreLocalization.customerExternalIDTooLong.localized
            )
        }

        if let siteCode, siteCode.unicodeScalars.count > 255 {
            throw CoreError.invalidCustomerIdentity(
                CoreLocalization.crmSiteCodeTooLong.localized
            )
        }

        if siteCustomerId != nil && siteCode == nil {
            throw CoreError.invalidCustomerIdentity(
                CoreLocalization.crmSiteCodeEmpty.localized
            )
        }

        return self
    }
}
