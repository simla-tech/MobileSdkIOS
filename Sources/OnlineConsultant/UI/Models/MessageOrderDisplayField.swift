//
//  ConsultantMessageOrderDisplayField.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 22.07.2026.
//

/// UI-ready order detail row displayed below the order items.
package struct MessageOrderDisplayField: Equatable, Sendable {

    /// Localized field title displayed on the left side of the row.
    package let title: String

    /// Field value displayed on the right side of the row.
    package let value: String

    package init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}
