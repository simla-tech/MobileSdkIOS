//
//  MessageOrderPayment.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Payment payload attached to an order message.
package struct MessageOrderPayment: Codable, Equatable, Sendable {

    /// Payment amount from backend `order.payments[].amount`.
    package let amount: MessageProductCost?

    /// Payment method name from backend `order.payments[].name`.
    package let name: String?

    /// Payment status payload from backend `order.payments[].status`.
    package let status: MessageOrderPaymentStatus?

    /// Creates a payment payload for an order message.
    package init(
        amount: MessageProductCost? = nil,
        name: String? = nil,
        status: MessageOrderPaymentStatus? = nil
    ) {
        self.amount = amount
        self.name = name
        self.status = status
    }
}

package extension MessageOrderPayment {

    /// Formatted payment label used by order message UI.
    var formattedLabel: String? {
        let label = [
            name?.nilIfEmpty,
            amount?.formattedMoneyLabel,
            status?.name?.nilIfEmpty
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        return label.isEmpty ? nil : label
    }
}
