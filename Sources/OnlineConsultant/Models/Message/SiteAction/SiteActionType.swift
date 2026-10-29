//
//  SiteActionType.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 20.07.2026.
//

/// Backend site action type.
package enum SiteActionType: Decodable, Equatable, Sendable {

    /// Contact form action.
    case contactForm

    /// Action type that is not supported by the current SDK.
    case unknown(String)

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "contact_form":
            self = .contactForm
        default:
            self = .unknown(value)
        }
    }
}
