import Foundation

/// Product payload attached to a product message.
package struct MessageProduct: Codable, Equatable, Sendable {

    /// Product display name from backend `product.name`.
    package let name: String?

    /// Product page URL from backend `product.url`.
    package let url: String?

    /// Product image URL from backend `product.img`.
    package let img: String?

    /// Product price payload from backend `product.cost`.
    package let cost: MessageProductCost?

    /// Fallback unit label from backend `product.unit`, used when `product.quantity.unit` is empty.
    package let unit: String?

    /// Product quantity and unit payload from backend `product.quantity`.
    package let quantity: MessageProductQuantity?

    /// Creates a product payload for a product message.
    package init(
        name: String? = nil,
        url: String? = nil,
        img: String? = nil,
        cost: MessageProductCost? = nil,
        unit: String? = nil,
        quantity: MessageProductQuantity? = nil
    ) {
        self.name = name
        self.url = url
        self.img = img
        self.cost = cost
        self.unit = unit
        self.quantity = quantity
    }
}
