//
//  ConnectedUser.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 14.08.2026.
//

import Core

package extension ConnectedUser {

    /// Returns a copy of the connected user with submitted contact form values applied.
    func applyingContactFormSubmitData(_ data: ContactFormSubmitData) -> ConnectedUser {
        ConnectedUser(
            token: token,
            name: data.name?.nilIfEmpty ?? name,
            email: data.email?.nilIfEmpty ?? email,
            phone: data.phone?.nilIfEmpty ?? phone
        )
    }
}
