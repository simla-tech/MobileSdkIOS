import Foundation

/// Identifies a persisted push status across retries and process restarts. Contains no site token.
public struct PushStatusRetryEvent: Equatable, Sendable {
    public let id: UUID
    public let pushID: String
    public let status: PushNotificationStatus
    public let changedAt: Int64
    public let buttonHash: String?

    package init(id: UUID, body: PushStatusRequestBody) {
        self.id = id
        self.pushID = body.pushId
        self.status = body.status
        self.changedAt = body.changedAt
        self.buttonHash = body.buttonHash
    }
}

/// Diagnostics for statuses that entered the retry queue. Initial requests are not included.
/// Callbacks run on the retry queue, off the main thread, and should return promptly.
public enum PushStatusRetryUpdate: Equatable, Sendable {
    /// Snapshot of an already pending status when the handler is assigned.
    case pending(PushStatusRetryEvent, attempts: Int, nextAttemptAt: Date)
    /// The first transient failure was saved for retry.
    case queued(PushStatusRetryEvent, PushStatusReportingError)
    /// A retry request is starting. Attempt numbers include the initial request.
    case sending(PushStatusRetryEvent, attempt: Int)
    /// The status is retained for a later attempt.
    case retryScheduled(PushStatusRetryEvent, nextAttempt: Int, nextAttemptAt: Date, error: PushStatusReportingError)
    /// The backend accepted this status, including acceptance by a separate duplicate report.
    case delivered(PushStatusRetryEvent)
    /// A permanent error ended retries, including rejection of a separate duplicate report.
    case rejected(PushStatusRetryEvent, PushStatusReportingError)
    /// The attempt limit was reached. The last error is unavailable after an interrupted final attempt.
    case dropped(PushStatusRetryEvent, attempts: Int, lastError: PushStatusReportingError?)
}

/// Owns one site-specific subscription without replacing subscriptions of other handlers.
package final class PushStatusRetryObservation {
    private let id = UUID()
    private let siteToken: String
    private let queue: PushStatusRetryQueue
    private let lock = NSLock()
    private var handler: ((PushStatusRetryUpdate) -> Void)?

    package init(siteToken: String, queue: PushStatusRetryQueue) {
        self.siteToken = siteToken
        self.queue = queue
    }

    package var onUpdate: ((PushStatusRetryUpdate) -> Void)? {
        get { lock.withLock { handler } }
        set {
            lock.withLock { handler = newValue }
            queue.observe(id: id, siteToken: siteToken, handler: newValue == nil ? nil : { [weak self] update in
                guard let self else { return }
                let callback = self.lock.withLock { self.handler }
                callback?(update)
            })
        }
    }

    deinit { queue.observe(id: id, siteToken: siteToken, handler: nil) }
}
