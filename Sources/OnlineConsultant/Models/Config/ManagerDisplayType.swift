//
//  ManagerDisplayType.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Known manager identity display modes returned in `config.manager_display_type`.
package enum ManagerDisplayType: String, Equatable, Sendable, CaseIterable {

    /// Use manager identity from the message/backend data.
    case standard

    /// Use custom manager identity from `manager_name` and `manager_logo`.
    case custom
}
