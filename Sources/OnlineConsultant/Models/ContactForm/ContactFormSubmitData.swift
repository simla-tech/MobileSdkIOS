/// Contact form values submitted by the SDK user.
///
/// The backend request body supports `name`, `email`, `phone`, `comment`, and `marketingConsent`.
/// `actionID` is sent separately as the `action_id` query parameter when the form belongs to a site
/// action. Personal data consent is validated locally by the UI and is not sent to the backend.
package struct ContactFormSubmitData: Equatable, Sendable {

    /// Customer name sent as `name`.
    package let name: String?

    /// Customer email sent as `email`.
    package let email: String?

    /// Customer phone sent as `phone`.
    package let phone: String?

    /// Customer comment sent as `comment`.
    package let comment: String?

    /// Optional marketing consent flag sent as `marketingConsent`.
    package let marketingConsent: Bool?

    /// Site action identifier sent as the `action_id` query parameter.
    package let actionID: FlexibleID?

    /// Local form scenario used by the SDK to choose the submit endpoint.
    package let kind: ContactFormKind

    /// Creates contact form submit data matching the backend contact-form contract.
    package init(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        comment: String? = nil,
        marketingConsent: Bool? = nil,
        actionID: FlexibleID? = nil,
        kind: ContactFormKind = .contact
    ) {
        self.name = name?.nilIfEmpty
        self.email = email?.nilIfEmpty
        self.phone = phone?.nilIfEmpty
        self.comment = comment?.nilIfEmpty
        self.marketingConsent = marketingConsent
        self.actionID = actionID
        self.kind = kind
    }
}

package extension ContactFormSubmitData {

    var submittedFields: [String: String] {
        [
            "name": name,
            "email": email,
            "phone": phone,
            "comment": comment
        ].compactMapValues { $0?.nilIfEmpty }
    }
}
