//
//  ConsultantMessagesResponse.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 20.07.2026.
//

/// Backend response for `GET /api/client/v1/messages`.
package struct ConsultantMessagesResponse: Decodable, Equatable {

    /// Messages returned by the backend in the `messages` field.
    package let messages: [ConsultantMessage]

    private enum CodingKeys: String, CodingKey {
        case messages
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([ConsultantMessage].self, forKey: .messages) ?? []
    }
}
