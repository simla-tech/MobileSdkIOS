//
//  ConsultantContactFormRequest.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Request body for `POST /api/client/v1/contact/form`.
///
/// The model matches the backend `ContactFormRequest` JSON contract. Required-field validation is
/// controlled by backend site/action settings and is not sent in the request body.
package struct ConsultantContactFormRequest: Encodable, Equatable {

    /// Customer name sent as `name`.
    package let name: String?

    /// Customer email sent as `email`.
    package let email: String?

    /// Customer phone sent as `phone`.
    package let phone: String?

    /// Customer comment sent as `comment`.
    package let comment: String?

    /// Optional marketing consent flag sent as `marketingConsent`.
    package let marketingConsent: Bool?

    package init(data: ContactFormSubmitData) {
        self.name = data.name?.nilIfEmpty
        self.email = data.email?.nilIfEmpty
        self.phone = data.phone?.nilIfEmpty
        self.comment = data.comment?.nilIfEmpty
        self.marketingConsent = data.marketingConsent
    }
}
