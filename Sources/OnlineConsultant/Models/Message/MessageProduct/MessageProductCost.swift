//
//  MessageProductCost.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Foundation

/// Product or order monetary amount payload.
package struct MessageProductCost: Codable, Equatable, Sendable {

    /// Numeric amount from backend `cost.value`.
    package let value: Double?

    /// Currency code from backend `cost.currency`, usually an ISO 4217 code such as `RUB` or `USD`.
    package let currency: String?

    /// Creates a monetary amount payload.
    package init(
        value: Double? = nil,
        currency: String? = nil
    ) {
        self.value = value
        self.currency = currency
    }
}

package extension MessageProductCost {

    /// Localized money label used by product and order message UI.
    var formattedMoneyLabel: String? {
        guard let value else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency

        if let currency = currency?.trimmingCharacters(in: .whitespacesAndNewlines), !currency.isEmpty {
            formatter.currencyCode = currency
        }

        if let label = formatter.string(from: NSNumber(value: value)) {
            return label
        }

        let valueLabel = String(format: "%.2f", value)
        let currencyLabel = currency?.trimmingCharacters(in: .whitespacesAndNewlines)

        return [valueLabel, currencyLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
