//
//  ConsultantMessageOrderDisplayItem.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 22.07.2026.
//

import Foundation

/// UI-ready order item displayed inside an order message bubble.
package struct MessageOrderDisplayItem: Equatable, Sendable {

    /// Display order number, for example `1.`.
    package let numberLabel: String

    /// Product name displayed for this order item.
    package let name: String

    /// Compact item details string, usually quantity and price.
    package let details: String

    /// Optional product URL opened when the item title is tapped.
    package let url: URL?

    package init(
        numberLabel: String,
        name: String,
        details: String,
        url: URL?
    ) {
        self.numberLabel = numberLabel
        self.name = name
        self.details = details
        self.url = url
    }
}
