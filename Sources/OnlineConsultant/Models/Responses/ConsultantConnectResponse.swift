//
//  ConsultantConnectResponse.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Core

/// The bootstrap response returned by `POST /api/client/v1/connect`.
///
/// The backend uses this response to return the current user, chat session, consultant configuration,
/// initial messages, and site actions required to start the consultant UI and realtime subscription.
package struct ConsultantConnectResponse: Decodable, Equatable, Sendable {

    /// The backend server timestamp encoded as the `ts` ISO 8601 string.
    package let timestamp: String?

    /// The connected consultant user.
    ///
    /// The user token from this object is used for authorized requests and WebSocket subscription.
    package let user: ConnectedUser

    /// The connected chat session.
    ///
    /// The session id from this object is used for authorized requests and WebSocket subscription.
    package let session: ConnectedSession

    /// Feature flags and runtime availability returned by the backend.
    package let behaviour: ConnectBehaviour?

    /// Runtime consultant configuration returned by the backend.
    package let config: ConsultantConfig?

    /// Initial message history returned by the backend.
    ///
    /// Missing `messages` is decoded as an empty array.
    package let messages: [ConsultantMessage]

    /// Site actions available for the current page and session.
    ///
    /// Missing `actions` is decoded as an empty array.
    package let actions: [SiteAction]

    private enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case user
        case session
        case behaviour
        case config
        case messages
        case actions
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        self.user = try container.decode(ConnectedUser.self, forKey: .user)
        self.session = try container.decode(ConnectedSession.self, forKey: .session)
        self.behaviour = try container.decodeIfPresent(ConnectBehaviour.self, forKey: .behaviour)
        self.config = try container.decodeIfPresent(ConsultantConfig.self, forKey: .config)
        self.messages = try container.decodeIfPresent([ConsultantMessage].self, forKey: .messages) ?? []
        self.actions = try container.decodeIfPresent([SiteAction].self, forKey: .actions) ?? []
    }

    package init(
        timestamp: String?,
        user: ConnectedUser,
        session: ConnectedSession,
        behaviour: ConnectBehaviour?,
        config: ConsultantConfig?,
        messages: [ConsultantMessage],
        actions: [SiteAction] = []
    ) {
        self.timestamp = timestamp
        self.user = user
        self.session = session
        self.behaviour = behaviour
        self.config = config
        self.messages = messages
        self.actions = actions
    }
}

package extension ConsultantConnectResponse {

    /// Returns a copy of the response with submitted contact form data applied to the connected user.
    func applyingContactFormSubmitData(_ data: ContactFormSubmitData) -> ConsultantConnectResponse {
        ConsultantConnectResponse(
            timestamp: timestamp,
            user: user.applyingContactFormSubmitData(data),
            session: session,
            behaviour: behaviour,
            config: config,
            messages: messages,
            actions: actions
        )
    }
}
