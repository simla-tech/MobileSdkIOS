//
//  ElementShape.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Known consultant element shapes returned in `config.element_shape`.
package enum ElementShape: String, Equatable, Sendable, CaseIterable {

    /// Rounded widconsultantget elements.
    case rounded

    /// Rectangular consultant elements.
    case rectangular = "rectangular form"
}
