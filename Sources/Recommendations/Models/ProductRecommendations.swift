import Foundation

/// Product recommendations returned by the backend.
public struct ProductRecommendations: Decodable, Equatable, Sendable {

    /// Core recommendation mechanic execution identifier used later for attribution events.
    public let executionID: UInt64

    /// Whether Core returned a personalized recommendation selection.
    public let personalized: Bool

    /// Core recommendation execution context.
    public let context: ProductRecommendationContext

    /// Recommended product ids that have available offers.
    public let productIds: [Int64]

    /// Recommended available product offers.
    public let products: [RecommendedProduct]

    private enum CodingKeys: String, CodingKey {
        case executionID = "executionId"
        case personalized
        case context
        case productIds
        case products
    }

    /// Creates a product recommendation selection.
    ///
    /// - Parameters:
    ///   - executionID: Identifier of the executed recommendation mechanic, used for attribution.
    ///   - personalized: Whether the recommendation selection is personalized.
    ///   - context: Mechanic execution context returned with the selection.
    ///   - productIds: IDs of recommended products with available offers.
    ///   - products: Available recommended product offers.
    public init(
        executionID: UInt64,
        personalized: Bool,
        context: ProductRecommendationContext,
        productIds: [Int64] = [],
        products: [RecommendedProduct] = []
    ) {
        self.executionID = executionID
        self.personalized = personalized
        self.context = context
        self.productIds = productIds
        self.products = products
    }

    /// Decodes a `ProductRecommendations` from the recommendations response.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executionID = try container.decode(UInt64.self, forKey: .executionID)
        personalized = try container.decode(Bool.self, forKey: .personalized)
        context = try container.decode(ProductRecommendationContext.self, forKey: .context)
        productIds = try container.decodeIfPresent([Int64].self, forKey: .productIds) ?? []
        products = try container.decodeIfPresent([RecommendedProduct].self, forKey: .products) ?? []
    }
}

/// Core recommendation execution context returned with a product selection.
public struct ProductRecommendationContext: Decodable, Equatable, Sendable {

    /// Core mechanic type, for example `personal` or `similar`.
    public let mechanicType: String

    /// Context fields required by the executed mechanic.
    public let required: [String]

    /// Creates a recommendation context value.
    ///
    /// - Parameters:
    ///   - mechanicType: Type of executed recommendation mechanic.
    ///   - required: Context fields required by the recommendation mechanic.
    public init(
        mechanicType: String,
        required: [String] = []
    ) {
        self.mechanicType = mechanicType
        self.required = required
    }

    /// Decodes a `ProductRecommendationContext` value from its serialized representation.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mechanicType = try container.decode(String.self, forKey: .mechanicType)
        self.required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case mechanicType
        case required
    }
}
