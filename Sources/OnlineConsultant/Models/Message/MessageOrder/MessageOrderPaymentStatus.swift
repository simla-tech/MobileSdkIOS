//
//  MessageOrderPaymentStatus.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Payment status payload attached to an order payment.
package struct MessageOrderPaymentStatus: Codable, Equatable, Sendable {

    /// Payment status display name from backend `order.payments[].status.name`.
    package let name: String?

    /// Payment execution indicator from backend `order.payments[].status.payed`.
    package let payed: Bool?

    /// Creates a payment status payload for an order message.
    package init(
        name: String? = nil,
        payed: Bool? = nil
    ) {
        self.name = name
        self.payed = payed
    }
}
