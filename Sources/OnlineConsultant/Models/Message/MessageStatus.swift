//
//  MessageStatus.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Message delivery status used by backend messages and SDK-generated local messages.
package enum MessageStatus: Codable, Equatable, Sendable, ExpressibleByStringLiteral {

    /// Backend zero status.
    case none

    /// Backend status for a newly created message before transport confirmation.
    case new

    /// Backend status for a message accepted by the transport layer.
    case sent

    /// Backend status for a message seen by the recipient.
    case seen

    /// Backend status for a deleted message.
    case deleted

    /// Backend or local status for a message that failed to send.
    case failed

    /// Frontend-compatible local status used before a real backend status is known.
    case undefined

    /// Local status for an outgoing message that is still being sent.
    case sending

    /// Frontend-compatible local status for synthetic messages that are already display-ready.
    case delivered

    /// Message status that is not known by this SDK version.
    case unknown(String)

    /// String value used in backend JSON payloads and local SDK payloads.
    package var rawValue: String {
        switch self {
        case .none:
            return "none"
        case .new:
            return "new"
        case .sent:
            return "sent"
        case .seen:
            return "seen"
        case .deleted:
            return "deleted"
        case .failed:
            return "failed"
        case .undefined:
            return "undefined"
        case .sending:
            return "sending"
        case .delivered:
            return "delivered"
        case .unknown(let value):
            return value
        }
    }

    /// Creates a message status from a backend or local SDK string value.
    package init(rawValue: String) {
        switch rawValue {
        case "none":
            self = .none
        case "new":
            self = .new
        case "sent":
            self = .sent
        case "seen":
            self = .seen
        case "deleted":
            self = .deleted
        case "failed":
            self = .failed
        case "undefined":
            self = .undefined
        case "sending":
            self = .sending
        case "delivered":
            self = .delivered
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
