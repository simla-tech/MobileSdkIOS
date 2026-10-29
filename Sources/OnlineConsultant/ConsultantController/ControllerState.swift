//
//  ControllerState.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

/// High-level lifecycle state published by `OnlineConsultantController`.
///
/// Represents whether the controller has no active session, is currently connecting, is ready, or
/// failed with a typed error. Host applications can observe this value to update chat
/// availability and loading UI without depending on internal SDK session details.
public enum ControllerState: Equatable, Sendable {

    /// No active connection.
    case idle
    /// Connection flow is in progress.
    case connecting
    /// Controller is connected and ready to work with the current session.
    /// `isAnonymous` is true when no customer identity was supplied for this session.
    case ready(isAnonymous: Bool)
    /// Connection or controller operation failed.
    case failed(ConsultantError)
}
