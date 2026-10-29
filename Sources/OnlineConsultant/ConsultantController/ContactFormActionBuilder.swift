import Foundation

/// Builds a local contact-form message from a supported site action.
package enum ContactFormActionBuilder {

    package static func message(
        from action: SiteAction,
        contactFormUser: ContactFormUser
    ) -> ConsultantMessage? {
        guard let contactForm = action.makeContactForm(for: contactFormUser) else {
            return nil
        }

        let timestamp = DateParser.string(from: Date())
        let items = action.messageItems

        return ConsultantMessage(
            id: FlexibleID("_action_\(action.id?.value ?? UUID().uuidString)"),
            content: contactForm.text,
            header: action.header?.nilIfEmpty,
            items: items.isEmpty ? nil : items,
            time: timestamp,
            updatedAt: timestamp,
            user: MessageUser(
                firstName: ConsultantLocalization.messageAuthorBotAssistant.localized
            ),
            fromMe: false,
            messageType: .contactForm,
            status: .delivered,
            contactForm: contactForm
        )
    }
}
