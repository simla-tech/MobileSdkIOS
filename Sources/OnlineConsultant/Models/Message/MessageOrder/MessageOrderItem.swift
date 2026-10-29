//
//  MessageOrderItem.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Order item payload attached to an order message.
package struct MessageOrderItem: Codable, Equatable, Sendable {

    /// Product name from backend `order.items[].name`.
    package let name: String?

    /// Product URL from backend `order.items[].url`.
    package let url: String?

    /// Item price from backend `order.items[].price`.
    package let price: MessageProductCost?

    /// Item quantity from backend `order.items[].quantity`.
    package let quantity: MessageProductQuantity?

    /// Creates an order item payload.
    package init(
        name: String? = nil,
        url: String? = nil,
        price: MessageProductCost? = nil,
        quantity: MessageProductQuantity? = nil
    ) {
        self.name = name
        self.url = url
        self.price = price
        self.quantity = quantity
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case url
        case price
        case quantity
    }
}

package extension MessageOrderItem {

    /// Formatted quantity and price details used by order message UI.
    var formattedDetails: String {
        let quantityLabel = quantity?.formattedOrderQuantityLabel(defaultUnit: nil)
        let priceLabel = price?.formattedMoneyLabel.map { "x \($0)" }
        let value = [quantityLabel, priceLabel]
            .compactMap { $0 }
            .joined(separator: " ")

        return value
    }
}
