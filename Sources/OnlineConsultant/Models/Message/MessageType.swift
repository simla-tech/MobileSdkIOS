//
//  MessageType.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Message type used by backend messages and SDK-generated local messages.
package enum MessageType: Codable, Equatable, Sendable, ExpressibleByStringLiteral {

    /// Plain text message.
    case text

    /// Backend system message.
    case system

    /// Backend command message.
    case command

    /// Order message.
    case order

    /// Product message.
    case product

    /// File attachment message.
    case file

    /// Image attachment message.
    case image

    /// Local SDK contact form message generated from site action data.
    case contactForm

    /// Message type that is not known by this SDK version.
    case unknown(String)

    /// String value used in backend JSON payloads and local SDK payloads.
    package var rawValue: String {
        switch self {
        case .text:
            return "text"
        case .system:
            return "system"
        case .command:
            return "command"
        case .order:
            return "order"
        case .product:
            return "product"
        case .file:
            return "file"
        case .image:
            return "image"
        case .contactForm:
            return "contact_form"
        case .unknown(let value):
            return value
        }
    }

    /// Creates a message type from a backend or local SDK string value.
    package init(rawValue: String) {
        switch rawValue {
        case "text":
            self = .text
        case "system":
            self = .system
        case "command":
            self = .command
        case "order":
            self = .order
        case "product":
            self = .product
        case "file":
            self = .file
        case "image":
            self = .image
        case "contact_form":
            self = .contactForm
        default:
            self = .unknown(rawValue)
        }
    }

    package init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
