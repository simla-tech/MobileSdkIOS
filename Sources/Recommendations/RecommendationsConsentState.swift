//
//  RecommendationsConsentState.swift
//  ConsultantSdk
//
//  Created by Yriy Deviataev on 16.10.2026.
//

/// User consent state for tracker events.
public enum RecommendationsConsentState: Equatable, Sendable {

    /// Consent has not been explicitly granted or denied.
    case unknown

    /// User granted permission to send tracker events.
    case granted

    /// User denied permission to send tracker events.
    case denied
}
