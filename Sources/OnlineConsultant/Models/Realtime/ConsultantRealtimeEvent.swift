//
//  ConsultantRealtimeEvent.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Foundation

/// Realtime event envelope received from the consultant backend.
///
/// Backend websocket events are JSON objects with `type` and `data` fields. Current backend emits
/// `message` and `offline_status`; unknown event types are preserved so the SDK can ignore them
/// without breaking the realtime stream, matching the web widget behaviour.
 package enum ConsultantRealtimeEvent: Decodable, Equatable, Sendable {

    /// Chat message event with a backend message payload.
    case message(ConsultantMessage)

    /// Manager availability event with an offline status payload.
    case offlineStatus(ConsultantOfflineStatus)

    /// Unsupported event type with its raw JSON payload.
    case unknown(type: String, data: ConsultantJSONValue?)

    /// Decodes a realtime event from a websocket text frame.
     package init(rawText: String) throws {
        let data = Data(rawText.utf8)
        self = try JSONDecoder().decode(ConsultantRealtimeEvent.self, from: data)
    }

    /// Backend event type string from the event envelope.
     package var type: String {
        switch self {
        case .message:
            return ConsultantRealtimeEventType.message.rawValue
        case .offlineStatus:
            return ConsultantRealtimeEventType.offlineStatus.rawValue
        case .unknown(let type, _):
            return type
        }
    }

    private enum CodingKeys: String, CodingKey {

        case type
        case data
    }

    /// Decodes the backend `type` and dispatches `data` to the matching payload model.
     package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case ConsultantRealtimeEventType.message.rawValue:
            self = .message(
                try container.decode(ConsultantMessage.self, forKey: .data)
            )
        case ConsultantRealtimeEventType.offlineStatus.rawValue:
            self = .offlineStatus(
                try container.decode(ConsultantOfflineStatus.self, forKey: .data)
            )
        default:
            self = .unknown(
                type: type,
                data: try container.decodeIfPresent(ConsultantJSONValue.self, forKey: .data)
            )
        }
    }
}

/// Known backend realtime event type values.
 private enum ConsultantRealtimeEventType: String, Codable, Equatable, Sendable {

    /// Chat message event.
    case message

    /// Manager availability event.
    case offlineStatus = "offline_status"
}
