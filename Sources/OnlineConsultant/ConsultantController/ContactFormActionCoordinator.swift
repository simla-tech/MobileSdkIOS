import Foundation

/// Selects and tracks the first displayable contact-form action.
@MainActor
package final class ContactFormActionCoordinator {

    private let client: OnlineConsultantClient
    private var shownActionIDs: Set<String> = []
    private var reportedShownActionIDs: Set<String> = []

    package init(client: OnlineConsultantClient) {
        self.client = client
    }

    package func reset() {
        shownActionIDs.removeAll()
        reportedShownActionIDs.removeAll()
    }

    package func initialContactFormMessageIfNeeded(
        actions: [SiteAction],
        contactFormUser: ContactFormUser,
        messagesAreEmpty: Bool,
        generation: UUID,
        isCurrentGeneration: @escaping (UUID) -> Bool,
        currentCredentials: @escaping () throws -> (sessionID: String, userToken: String),
        handleError: @escaping (Error) -> Void
    ) -> ConsultantMessage? {
        guard messagesAreEmpty else {
            return nil
        }

        guard let (action, message) = actions.lazy.compactMap({ action -> (SiteAction, ConsultantMessage)? in
            if let actionID = action.id?.value, self.shownActionIDs.contains(actionID) {
                return nil
            }

            guard let message = ContactFormActionBuilder.message(
                from: action,
                contactFormUser: contactFormUser
            ) else {
                return nil
            }

            return (action, message)
        }).first else {
            return nil
        }

        if let actionID = action.id?.value {
            shownActionIDs.insert(actionID)
            startActionLifecycle(
                actionID: actionID,
                generation: generation,
                isCurrentGeneration: isCurrentGeneration,
                currentCredentials: currentCredentials,
                handleError: handleError
            )
        }

        return message
    }

    private func startActionLifecycle(
        actionID: String,
        generation: UUID,
        isCurrentGeneration: @escaping (UUID) -> Bool,
        currentCredentials: @escaping () throws -> (sessionID: String, userToken: String),
        handleError: @escaping (Error) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }

            await executeAction(
                actionID: actionID,
                generation: generation,
                isCurrentGeneration: isCurrentGeneration,
                currentCredentials: currentCredentials,
                handleError: handleError
            )
            await showActionIfNeeded(
                actionID: actionID,
                generation: generation,
                isCurrentGeneration: isCurrentGeneration,
                currentCredentials: currentCredentials,
                handleError: handleError
            )
        }
    }

    private func executeAction(
        actionID: String,
        generation: UUID,
        isCurrentGeneration: (UUID) -> Bool,
        currentCredentials: () throws -> (sessionID: String, userToken: String),
        handleError: (Error) -> Void
    ) async {
        do {
            let credentials = try currentCredentials()
            _ = try await client.executeAction(
                actionID: actionID,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )
        } catch {
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }

            handleError(error)
        }
    }

    private func showActionIfNeeded(
        actionID: String,
        generation: UUID,
        isCurrentGeneration: (UUID) -> Bool,
        currentCredentials: () throws -> (sessionID: String, userToken: String),
        handleError: (Error) -> Void
    ) async {
        guard !reportedShownActionIDs.contains(actionID) else {
            return
        }

        do {
            let credentials = try currentCredentials()
            try await client.showAction(
                actionID: actionID,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }

            reportedShownActionIDs.insert(actionID)
        } catch {
            guard isCurrentGeneration(generation), !Task.isCancelled else { return }

            handleError(error)
        }
    }
}
