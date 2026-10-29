/// Component responsible for resolving contact form presentation state.
///
/// It combines backend consultant configuration, current messages, offline state,
/// and known visitor contact data to decide whether the form is hidden, visible,
/// or waiting until the visitor sends the first message.
/// Describes how the SDK should present the contact form in the current conversation state.
package enum ContactFormPresentation: Equatable, Sendable {

    /// The contact form should not be shown.
    case hidden
    /// The contact form should be shown immediately.
    case visible(ContactForm)
    /// The contact form should be shown after the visitor sends the first message.
    case waitingForFirstMessage(ContactForm)

    /// Builds the presentation state from backend configuration, loaded messages, and visitor data.
    package static func make(
        response: ConsultantConnectResponse,
        messages: [ConsultantMessage],
        isOffline: Bool,
        user: ContactFormUser
    ) -> ContactFormPresentation {
        guard
            !isOffline,
            response.config?.useContactForm == true,
            let fields = response.config?.contactForm?.fields,
            !fields.isEmpty
        else {
            return .hidden
        }

        let requiresContactForm = fields.contains { field, config in
            switch field {
            case .personalData:
                return false
            case .marketingConsent:
                return config.required
            default:
                return config.required && !user.hasFilledValue(for: field)
            }
        }

        guard requiresContactForm else {
            return .hidden
        }

        let display = response.config?.contactFormDisplay ?? .afterFirstMessage
        let contactForm = ContactForm(
            text: response.config?.contactFormText,
            display: display,
            fields: fields,
            prefill: ContactFormPrefill(
                name: user.name,
                email: user.email,
                phone: user.phone
            )
        )

        switch display {
        case .atBeginningDialogue:
            return messages.contains { !$0.isVirtualSupportMessage }
                ? .hidden
                : .visible(contactForm)
        case .afterFirstMessage:
            return messages.containsVisitorMessage
                ? .visible(contactForm)
                : .waitingForFirstMessage(contactForm)
        }
    }
}
