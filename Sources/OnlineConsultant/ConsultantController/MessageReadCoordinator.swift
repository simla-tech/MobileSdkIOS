import Foundation

/// Coordinator for backend message read-state updates.
///
/// Coalesces visible incoming message ids into one debounced backend `read` request, keeps only the
/// greatest pending backend message id, and ignores ids that were already submitted during the
/// current controller lifecycle.
@MainActor
package final class MessageReadCoordinator {

    private let client: OnlineConsultantClient
    private let debounceNanoseconds: UInt64
    private var pendingMessageID: UInt64?
    private var lastSubmittedMessageID: UInt64?
    private var readTask: Task<Void, Never>?
    private var generation = UUID()

    /// Creates a coordinator with the client used for backend read requests.
    package init(
        client: OnlineConsultantClient,
        debounceNanoseconds: UInt64 = 500_000_000
    ) {
        self.client = client
        self.debounceNanoseconds = debounceNanoseconds
    }

    /// Schedules a debounced read-state update for the provided backend message id.
    package func schedule(
        messageID: String,
        session: String,
        userToken: String,
        handleError: @escaping (Error) -> Void
    ) {
        guard let numericMessageID = UInt64(messageID) else {
            return
        }

        if let lastSubmittedMessageID, numericMessageID <= lastSubmittedMessageID {
            return
        }

        if let pendingMessageID, numericMessageID <= pendingMessageID {
            return
        }

        pendingMessageID = numericMessageID
        readTask?.cancel()

        let generation = generation
        let debounceNanoseconds = debounceNanoseconds
        readTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }

            await self?.flush(
                generation: generation,
                session: session,
                userToken: userToken,
                handleError: handleError
            )
        }
    }

    /// Cancels a pending read-state update without clearing the last submitted id.
    package func cancel() {
        readTask?.cancel()
        readTask = nil
        pendingMessageID = nil
        generation = UUID()
    }

    /// Cancels pending work and clears submitted read-state tracking.
    package func reset() {
        cancel()
        lastSubmittedMessageID = nil
    }

    private func flush(
        generation: UUID,
        session: String,
        userToken: String,
        handleError: @escaping (Error) -> Void
    ) async {
        guard self.generation == generation, let messageID = pendingMessageID else {
            return
        }

        pendingMessageID = nil
        readTask = nil

        do {
            try await client.markMessageRead(
                messageID: String(messageID),
                session: session,
                userToken: userToken
            )
            guard self.generation == generation, !Task.isCancelled else {
                return
            }

            lastSubmittedMessageID = max(lastSubmittedMessageID ?? 0, messageID)
        } catch {
            guard self.generation == generation, !Task.isCancelled else {
                return
            }

            handleError(error)
        }
    }
}
