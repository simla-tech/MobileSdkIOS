//
//  ContactFormField.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Backend contact form field configuration.
package struct ContactFormField: Codable, Equatable, Sendable {

    /// Indicates that the visitor must fill or accept this field before submit.
    package let required: Bool

    /// Creates a contact form field configuration.
    package init(required: Bool = false) {
        self.required = required
    }
}
