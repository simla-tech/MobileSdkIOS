//
//  ConsultantSendMessageResponse.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 21.07.2026.
//

/// Backend response for `POST /api/client/v1/messages`.
package struct ConsultantSendMessageResponse: Decodable, Equatable, Sendable {

    /// Metadata for the message created or failed by the backend.
    package let message: ConsultantSentMessage

    package init(message: ConsultantSentMessage) {
        self.message = message
    }
}

/// Backend acknowledgement for a sent message.
 package struct ConsultantSentMessage: Decodable, Equatable, Sendable {

    /// Backend message identifier returned in the `message.id` field.
     package let id: String

    /// Backend creation time returned in the `message.time` field.
     package let time: String

    /// Backend update time returned in the `message.updated_at` field.
     package let updatedAt: String?

    /// Backend delivery status returned in the `message.status` field.
     package let status: MessageStatus

    private enum CodingKeys: String, CodingKey {

        case id
        case time
        case updatedAt = "updated_at"
        case status
    }

    package init(
        id: String,
        time: String,
        updatedAt: String?,
        status: MessageStatus
    ) {
        self.id = id
        self.time = time
        self.updatedAt = updatedAt
        self.status = status
    }
}
