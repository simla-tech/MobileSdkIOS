//
//  MessageProductQuantity.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Product or order item quantity payload.
package struct MessageProductQuantity: Codable, Equatable, Sendable {

    /// Numeric quantity from backend `quantity.value`.
    package let value: Double?

    /// Display unit from backend `quantity.unit`, such as `pcs` or a localized catalog unit.
    package let unit: String?

    /// Creates a quantity payload.
    package init(
        value: Double? = nil,
        unit: String? = nil
    ) {
        self.value = value
        self.unit = unit
    }
}

package extension MessageProductQuantity {

    /// Formats quantity for order item rows, using the fallback unit when `unit` is empty.
    func formattedOrderQuantityLabel(defaultUnit: String?) -> String? {
        guard let value else {
            return nil
        }

        let amountLabel: String
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            amountLabel = String(Int64(value))
        } else {
            amountLabel = String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }

        let unitLabel = unit?.nilIfEmpty ?? defaultUnit?.nilIfEmpty
        return [amountLabel, unitLabel]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

package extension MessageProductQuantity {

    /// Indicates whether the quantity represents an available product.
    var isAvailable: Bool {
        (value ?? 0) > 0
    }

    /// Formats quantity for product messages, including the availability text.
    func formattedQuantityLabel(defaultUnit: String?) -> String? {
        guard let value else {
            return nil
        }

        guard value > 0 else {
            return ConsultantLocalization.productQuantityUnavailable.localized
        }

        let amountLabel: String
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            amountLabel = String(Int64(value))
        } else {
            amountLabel = String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }

        let unitLabel = unit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? unit
            : defaultUnit

        return [
            ConsultantLocalization.productQuantityAvailable.localized,
            amountLabel,
            unitLabel
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
