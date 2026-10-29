import Core
import Foundation

/// Product recommendation parameters. The SDK supplies the customer from the shared session.
public struct ProductRecommendationsRequest: Encodable, Equatable, Sendable {

    /// Symbolic Core mechanic code.
    public let mechanicCode: String

    /// retailCRM product id used by product-based recommendations.
    public let productID: Int64?

    /// retailCRM product external id used by product-based recommendations.
    public let productExternalID: String?

    /// retailCRM offer id used by product-based recommendations.
    public let offerID: Int64?

    /// retailCRM offer external id used by product-based recommendations.
    public let offerExternalID: String?

    /// Recommendation block code.
    public let blockCode: String

    /// Creates a product recommendations request.
    ///
    /// - Parameters:
    ///   - mechanicCode: Nonempty mechanic code.
    ///   - blockCode: Nonempty code of the recommendation placement.
    ///   - productID: Internal product ID used as recommendation context.
    ///   - productExternalID: External product ID used as recommendation context.
    ///   - offerID: Internal offer ID used as recommendation context.
    ///   - offerExternalID: External offer ID used as recommendation context.
    public init(
        mechanicCode: String,
        blockCode: String,
        productID: Int64? = nil,
        productExternalID: String? = nil,
        offerID: Int64? = nil,
        offerExternalID: String? = nil
    ) {
        self.mechanicCode = mechanicCode
        self.blockCode = blockCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.productID = productID
        self.productExternalID = productExternalID?.nilIfEmpty
        self.offerID = offerID
        self.offerExternalID = offerExternalID?.nilIfEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case mechanicCode = "mechanic_code"
        case productID = "product_id"
        case productExternalID = "product_external_id"
        case offerID = "offer_id"
        case offerExternalID = "offer_external_id"
        case blockCode = "block_code"
    }
}

package extension ProductRecommendationsRequest {

    func validate() throws {
        guard !mechanicCode.isEmpty else {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.mechanicCodeEmpty.localized
            )
        }

        guard !blockCode.isEmpty else {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.blockCodeEmpty.localized
            )
        }

        if let productID, productID <= 0 {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.productIDInvalid.localized
            )
        }

        if let offerID, offerID <= 0 {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.offerIDInvalid.localized
            )
        }

        guard productID == nil || productExternalID == nil else {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.productContextConflict.localized
            )
        }

        guard offerID == nil || offerExternalID == nil else {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.offerContextConflict.localized
            )
        }

        let hasProductContext = productID != nil || productExternalID != nil
        let hasOfferContext = offerID != nil || offerExternalID != nil
        guard !hasProductContext || !hasOfferContext else {
            throw RecommendationsError.invalidRequest(
                RecommendationsLocalization.productAndOfferConflict.localized
            )
        }
    }
}

/// Adds the current session's customer identity to the backend request.
package struct ProductRecommendationsRequestBody: Encodable {
    package let request: ProductRecommendationsRequest
    package let customerIdentity: CrmSdkCustomerIdentity?

    private enum CodingKeys: String, CodingKey {
        case systemCustomerID = "system_customer_id"
        case systemCustomerExternalID = "system_customer_external_id"
    }

    package func encode(to encoder: Encoder) throws {
        try request.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let customerID = customerIdentity?.customerId {
            try container.encode(customerID, forKey: .systemCustomerID)
        } else {
            try container.encodeIfPresent(
                customerIdentity?.siteCustomerId?.nilIfEmpty,
                forKey: .systemCustomerExternalID
            )
        }
    }

    package init(request: ProductRecommendationsRequest, customerIdentity: CrmSdkCustomerIdentity?) {
        self.request = request
        self.customerIdentity = customerIdentity
    }
}
