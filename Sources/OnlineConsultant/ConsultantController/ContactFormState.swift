/// Local state holder for contact-form presentation and prefilled user data.
///
/// Derives contact-form user fields from the connected backend user and SDK fallback user, tracks
/// whether contact and offline forms have already been submitted locally, merges submitted data back
/// into local state, and calculates whether the current contact form should be shown or hidden.

import Core

package struct ContactFormState {

    private var hasSubmittedContactForm = false
    package private(set) var hasSubmittedOfflineForm = false
    package private(set) var user = ContactFormUser()

    /// Clears local contact-form state.
    package mutating func reset() {
        hasSubmittedContactForm = false
        hasSubmittedOfflineForm = false
        user = ContactFormUser()
    }

    /// Applies connected backend user data and SDK-provided fallback user values.
    package mutating func applyConnectedUser(
        _ connectedUser: ConnectedUser,
        fallbackUser: ConnectUser
    ) {
        hasSubmittedContactForm = false
        hasSubmittedOfflineForm = false
        user = ContactFormUser(
            connectedUser: connectedUser,
            fallbackUser: fallbackUser
        )
    }

    /// Applies submitted form data to local user state.
    package mutating func applySubmitData(
        _ data: ContactFormSubmitData,
        kind: ContactFormKind = .contact
    ) {
        switch kind {
        case .contact:
            hasSubmittedContactForm = true
        case .offline:
            hasSubmittedOfflineForm = true
        }
        user = user.merging(data)
    }

    /// Returns whether a form of the provided kind has already been submitted locally.
    package func hasSubmittedForm(kind: ContactFormKind) -> Bool {
        switch kind {
        case .contact:
            return hasSubmittedContactForm
        case .offline:
            return hasSubmittedOfflineForm
        }
    }

    /// Calculates current contact-form presentation state.
    package func presentation(
        response: ConsultantConnectResponse?,
        messages: [ConsultantMessage],
        isOffline: Bool
    ) -> ContactFormPresentation {
        guard !hasSubmittedContactForm else {
            return .hidden
        }

        guard let response else {
            return .hidden
        }

        return ContactFormPresentation.make(
            response: response,
            messages: messages,
            isOffline: isOffline,
            user: user
        )
    }

    package init(
        hasSubmittedContactForm: Bool = false,
        hasSubmittedOfflineForm: Bool = false,
        user: ContactFormUser = ContactFormUser()
    ) {
        self.hasSubmittedContactForm = hasSubmittedContactForm
        self.hasSubmittedOfflineForm = hasSubmittedOfflineForm
        self.user = user
    }
}
