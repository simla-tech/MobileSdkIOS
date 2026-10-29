//
//  ControllerInternalState.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 24.07.2026.
//

/// Internal lifecycle state used by SDK UI.
///
/// Mirrors the public controller state but keeps the ready-state snapshot available for internal
/// UIKit components that need messages, consultant configuration, pagination, and contact-form state
/// atomically.
package enum ControllerInternalState: Equatable, Sendable {

    /// No active connection.
    case idle
    /// Connection flow is in progress.
    case connecting
    /// Controller is connected and has a current state snapshot for SDK UI.
    case ready(ControllerSnapshot)
    /// Connection or controller operation failed with a user-readable message.
    case failed(String)
}
