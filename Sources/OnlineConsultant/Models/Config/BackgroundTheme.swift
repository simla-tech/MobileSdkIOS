//
//  BackgroundTheme.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Known consultant background themes returned in `config.bg_color`.
package enum BackgroundTheme: String, Equatable, Sendable, CaseIterable {

    /// Light consultant background theme.
    case light

    /// Dark consultant background theme.
    case dark
}
