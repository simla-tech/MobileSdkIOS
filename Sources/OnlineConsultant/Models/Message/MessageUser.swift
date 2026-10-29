//
//  MessageUser.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Sender payload attached to a consultant message.
package struct MessageUser: Codable, Equatable, Sendable {

    /// Sender first name from backend `message.user.first_name`.
    package let firstName: String?

    /// Sender last name from backend `message.user.last_name`.
    package let lastName: String?

    /// Sender avatar URL from backend `message.user.avatar`.
    package let avatar: String?

    /// Creates a message sender payload.
    package init(
        firstName: String? = nil,
        lastName: String? = nil,
        avatar: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
    }

    private enum CodingKeys: String, CodingKey {

        case firstName = "first_name"
        case lastName = "last_name"
        case avatar
    }
}

package extension MessageUser {

    func displayName(isOutgoing: Bool) -> String {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return name.isEmpty
            ? Self.fallbackDisplayName(isOutgoing: isOutgoing)
            : name
    }

    static func fallbackDisplayName(isOutgoing: Bool) -> String {
        isOutgoing
            ? ConsultantLocalization.messageAuthorVisitor.localized
            : ConsultantLocalization.messageAuthorConsultant.localized
    }
}
