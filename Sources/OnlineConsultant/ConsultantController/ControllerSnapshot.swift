//
//  ControllerSnapshot.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

/// Immutable ready-state snapshot used inside `ConsultantController`.
///
/// Bundles the latest backend connect response, active credentials, messages, consultant configuration,
/// offline state, unread incoming-message badge state, pagination flag, and contact-form
/// presentation into one value that SDK UI code can consume atomically.
package struct ControllerSnapshot: Equatable, Sendable {

    /// Latest backend connect response.
    package let connectResponse: ConsultantConnectResponse
    /// User token used for authorized backend requests.
    package let userToken: String?
    /// Session id used for authorized backend requests.
    package let sessionID: String?
    /// Messages available in the current controller state.
    package let messages: [ConsultantMessage]
    /// consultant configuration received from the backend.
    package let consultantConfig: ConsultantConfig?
    /// Indicates whether the consultant is currently offline.
    package let isOffline: Bool
    /// Indicates whether the message input must be hidden by active offline mode.
    package let blocksMessageInput: Bool
    /// Number of unread incoming messages in the loaded history; zero when the counter is disabled.
    package let unreadIncomingMessagesCount: Int
    /// Indicates whether older messages can be loaded.
    package let canLoadOlderMessages: Bool
    /// Current contact-form presentation state.
    package let contactFormPresentation: ContactFormPresentation

    package init(
        connectResponse: ConsultantConnectResponse,
        userToken: String?,
        sessionID: String?,
        messages: [ConsultantMessage],
        consultantConfig: ConsultantConfig?,
        isOffline: Bool,
        blocksMessageInput: Bool,
        unreadIncomingMessagesCount: Int,
        canLoadOlderMessages: Bool,
        contactFormPresentation: ContactFormPresentation
    ) {
        self.connectResponse = connectResponse
        self.userToken = userToken
        self.sessionID = sessionID
        self.messages = messages
        self.consultantConfig = consultantConfig
        self.isOffline = isOffline
        self.blocksMessageInput = blocksMessageInput
        self.unreadIncomingMessagesCount = unreadIncomingMessagesCount
        self.canLoadOlderMessages = canLoadOlderMessages
        self.contactFormPresentation = contactFormPresentation
    }
}
