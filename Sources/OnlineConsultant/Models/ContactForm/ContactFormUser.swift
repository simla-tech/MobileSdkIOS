//
//  ContactFormUser.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Core

/// Local contact-form user state used to prefill supported contact fields and decide whether a
/// contact form is still required.
///
/// The backend persists submitted `name`, `email`, and `phone` values on the consultant user.
/// Submit-only values such as `comment`, `marketingConsent`, and personal-data consent are not part
/// of this model.
package struct ContactFormUser: Equatable, Sendable {

    /// User name used for the `name` field prefill and required-field checks.
    package let name: String?

    /// Email address used for the `email` field prefill and required-field checks.
    package let email: String?

    /// Phone number used for the `phone` field prefill and required-field checks.
    package let phone: String?

    /// Creates contact-form user state from known contact values.
    package init(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.name = name?.nilIfEmpty
        self.email = email?.nilIfEmpty
        self.phone = phone?.nilIfEmpty
    }

    /// Builds contact-form user state from the connected backend user and SDK-provided fallback
    /// user data.
    package init(
        connectedUser: ConnectedUser,
        fallbackUser: ConnectUser
    ) {
        self.init(
            name: connectedUser.name?.nilIfEmpty ?? fallbackUser.name?.nilIfEmpty,
            email: connectedUser.email?.nilIfEmpty ?? fallbackUser.email?.nilIfEmpty,
            phone: connectedUser.phone?.nilIfEmpty ?? fallbackUser.phone?.nilIfEmpty
        )
    }

    /// Returns a copy with backend-persisted contact fields from submitted form data applied.
    package func merging(_ data: ContactFormSubmitData) -> ContactFormUser {
        .init(
            name: data.name?.nilIfEmpty ?? name,
            email: data.email?.nilIfEmpty ?? email,
            phone: data.phone?.nilIfEmpty ?? phone
        )
    }
}

package extension ContactFormUser {

    /// Returns whether a supported contact field already has a non-empty value.
    func hasFilledValue(for field: ContactFormFieldKey) -> Bool {
        switch field {
        case .name:
            return name?.isEmpty == false
        case .email:
            return email?.isEmpty == false
        case .phone:
            return phone?.isEmpty == false
        default:
            return false
        }
    }
}
