//
//  ContactFormDisplay.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// Known contact form display strategies returned in `config.contact_form_display`.
package enum ContactFormDisplay: String, Codable, Equatable, Sendable {

    /// Show the contact form before the visitor sends the first message.
    case atBeginningDialogue = "at_beginning_dialogue"

    /// Show the contact form after the visitor sends the first message.
    case afterFirstMessage = "after_first_message"
}
