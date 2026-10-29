import Foundation

/// Available product offer returned in a recommendation selection.
public struct RecommendedProduct: Decodable, Equatable, Sendable {

    /// retailCRM offer id.
    public let id: Int64

    /// retailCRM product id.
    public let productID: Int64

    /// Offer name, or product name when offer name is empty.
    public let name: String

    /// Current offer price.
    public let price: Double

    /// Previous offer price.
    public let oldPrice: Double

    /// Price currency.
    public let currency: String

    /// Offer image URL, or product image URL when offer image is empty.
    public let imageUrl: String

    /// Product URL.
    public let url: String

    /// Availability flag returned by the backend.
    public let available: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case productID = "productId"
        case name, price, oldPrice, currency, imageUrl, url, available
    }

    /// Decodes a `RecommendedProduct` from the recommendations response.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        productID = try container.decode(Int64.self, forKey: .productID)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)
        oldPrice = try container.decodeIfPresent(Double.self, forKey: .oldPrice) ?? 0
        currency = try container.decode(String.self, forKey: .currency)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}
