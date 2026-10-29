//
//  ConsultantSendMessageRequest.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Core

/// Backend request for `POST /api/client/v1/messages`.
package struct ConsultantSendMessageRequest: Encodable, Equatable {

    /// Message payload sent in the required `message` field.
    package let message: ConsultantSendMessageBody

    /// User contact data sent in the optional `user` field.
    package let user: ConnectUser

    package init(
        message: ConsultantSendMessageBody,
        user: ConnectUser = ConnectUser()
    ) {
        self.message = message
        self.user = user
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case user
    }
}

/// Message body for `ConsultantSendMessageRequest.message`.
package struct ConsultantSendMessageBody: Encodable, Equatable {

    /// Backend message type sent in `message.type`.
    package let type: MessageType

    /// Text content sent in `message.text`.
    package let text: String?

    /// File/image items sent in `message.items`.
    package let items: [ConsultantSendMessageItem]?

    package init(
        type: MessageType,
        text: String? = nil,
        items: [ConsultantSendMessageItem]? = nil
    ) {
        self.type = type
        self.text = text
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case items
    }
}

/// File or image item sent in `message.items`.
///
/// The backend request item contains the uploaded file identifier and optional caption.
package struct ConsultantSendMessageItem: Encodable, Equatable {

    /// Uploaded or preinstalled file identifier sent in `items[].id`.
    package let id: String

    /// Optional file caption sent in `items[].caption`.
    package let caption: String?

    package init(
        id: String,
        caption: String? = nil
    ) {
        self.id = id
        self.caption = caption
    }
}
