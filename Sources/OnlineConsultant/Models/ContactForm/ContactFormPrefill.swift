//
//  ContactFormPrefill.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// User contact values used to prefill a contact form.
package struct ContactFormPrefill: Codable, Equatable, Sendable {

    /// Prefilled visitor name.
    package let name: String?

    /// Prefilled visitor email.
    package let email: String?

    /// Prefilled visitor phone.
    package let phone: String?

    /// Creates prefilled contact values.
    package init(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.name = name
        self.email = email
        self.phone = phone
    }
}
