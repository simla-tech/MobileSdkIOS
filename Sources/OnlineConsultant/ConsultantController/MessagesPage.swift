//
//  MessagesPage.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

/// Result returned after loading an older page of consultant messages.
///
/// Carries the messages returned by the backend for the requested offset and a pagination hint that
/// tells UI code whether another older page is likely available.
 package struct MessagesPage: Equatable, Sendable {

    /// Messages returned by the backend for the requested page.
     package let messages: [ConsultantMessage]
    /// Indicates whether another older page is likely available.
     package let hasMoreMessages: Bool

    /// Creates a messages page result.
     package init(messages: [ConsultantMessage], hasMoreMessages: Bool) {
        self.messages = messages
        self.hasMoreMessages = hasMoreMessages
    }
}
