//
//  ControllerEvent.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

/// Discrete controller events emitted in addition to state and message streams.
///
/// Provides host applications with important one-time notifications such as successful connection,
/// decoded realtime payloads, contact-form submission, offline status changes, and operation errors.
 package enum ControllerEvent: Equatable, Sendable {

    /// Controller state changed.
    case stateChanged(ControllerState)
    /// Loaded unread incoming-message count changed.
    case unreadIncomingMessagesCountChanged(Int)
    /// Connect flow completed successfully.
    case connected(ConsultantConnectResponse)
    /// Backend realtime event was received and decoded.
    case realtimeEvent(ConsultantRealtimeEvent)
    /// Contact form was submitted successfully.
    case contactFormSubmitted(ContactFormSubmitData)
    /// Consultant offline state changed.
    case offlineStatusChanged(Bool)
    /// Controller operation failed with a user-readable message.
    case error(String)
}
