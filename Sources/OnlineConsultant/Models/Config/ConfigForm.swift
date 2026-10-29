//
//  ConfigForm.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Contact form field configuration returned by the backend.
package struct ConfigForm: Decodable, Equatable, Sendable {

    /// Configured contact form fields keyed by typed backend field key.
    package let fields: [ContactFormFieldKey: ContactFormField]

    private enum CodingKeys: String, CodingKey {
        case name
        case email
        case phone
        case comment
        case personalData
        case marketingConsent
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fields = Dictionary(backendFields: [
            "name": try container.decodeIfPresent(ContactFormField.self, forKey: .name),
            "email": try container.decodeIfPresent(ContactFormField.self, forKey: .email),
            "phone": try container.decodeIfPresent(ContactFormField.self, forKey: .phone),
            "comment": try container.decodeIfPresent(ContactFormField.self, forKey: .comment),
            "personalData": try container.decodeIfPresent(
                ContactFormField.self,
                forKey: .personalData
            ),
            "marketingConsent": try container.decodeIfPresent(
                ContactFormField.self,
                forKey: .marketingConsent
            )
        ].compactMapValues { $0 })
    }
}
