//
//  MessageOrderDelivery.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Delivery payload attached to an order message.
package struct MessageOrderDelivery: Codable, Equatable, Sendable {

    /// Delivery address from backend `order.delivery.address`.
    package let address: String?

    /// Delivery comment from backend `order.delivery.comment`.
    package let comment: String?

    /// Delivery method name from backend `order.delivery.name`.
    package let name: String?

    /// Delivery price from backend `order.delivery.price`.
    package let price: MessageProductCost?

    /// Creates a delivery payload for an order message.
    package init(
        address: String? = nil,
        comment: String? = nil,
        name: String? = nil,
        price: MessageProductCost? = nil
    ) {
        self.address = address
        self.comment = comment
        self.name = name
        self.price = price
    }
}
