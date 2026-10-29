import Foundation
import SDKConfiguration
import Network

/// Persistent retries within the current application or notification-extension container.
/// The first attempt's completion is independent of retries and does not hold notification delivery.
package final class PushStatusRetryQueue: @unchecked Sendable {
    package static let shared = PushStatusRetryQueue()

    private let queue = DispatchQueue(label: "com.retailcrm.push-status-retries")
    private let storage: PushStatusRetryStorage
    private let baseDelay: TimeInterval
    private let maxAttempts: Int
    private let monitor: NWPathMonitor?
    private var session: (any PushNetworkSession)?
    private var pending: [UUID: PendingPushStatus] = [:]
    private var isSending = false
    private var isNetworkAvailable = true
    private var scheduled: DispatchWorkItem?
    private var observers: [UUID: (siteToken: String, handler: (PushStatusRetryUpdate) -> Void)] = [:]

    package init(
        storage: PushStatusRetryStorage = .init(),
        baseDelay: TimeInterval = 10,
        maxAttempts: Int = 5,
        monitorsNetwork: Bool = true
    ) {
        self.storage = storage
        self.baseDelay = baseDelay
        self.maxAttempts = max(1, maxAttempts)
        self.isNetworkAvailable = !monitorsNetwork
        self.monitor = monitorsNetwork ? NWPathMonitor() : nil
        do {
            for entry in try storage.loadPending() { pending[entry.id] = entry }
        } catch {
            NSLog("RetailCRM push status retries could not be restored: %@", error.localizedDescription)
        }
        monitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.queue.async {
                self.isNetworkAvailable = path.status == .satisfied
                self.scheduleNext()
            }
        }
        monitor?.start(queue: queue)
    }

    deinit {
        scheduled?.cancel()
        monitor?.cancel()
    }

    /// Restores retry scheduling when a reporter is created after a process restart.
    package func resume(using session: any PushNetworkSession) {
        queue.async {
            self.session = session
            self.scheduleNext()
        }
    }

    package func observe(id: UUID, siteToken: String, handler: ((PushStatusRetryUpdate) -> Void)?) {
        queue.async {
            guard let handler else {
                self.observers.removeValue(forKey: id)
                return
            }
            self.observers[id] = (siteToken, handler)
            for entry in self.pending.values.filter({ $0.siteToken == siteToken })
                .sorted(by: { $0.nextAttemptAt < $1.nextAttemptAt }) {
                handler(.pending(entry.event, attempts: entry.attempts, nextAttemptAt: entry.nextAttemptAt))
            }
        }
    }

    private func publish(_ update: PushStatusRetryUpdate, siteToken: String) {
        for observer in observers.values where observer.siteToken == siteToken {
            observer.handler(update)
        }
    }

    package func enqueue(
        _ body: PushStatusRequestBody,
        siteToken: String,
        clientAPIEndpointURL: URL = BackendEndpoints().clientAPIEndpointURL,
        retryAfter: TimeInterval?,
        error: PushStatusReportingError,
        completion: @escaping () -> Void
    ) {
        queue.async {
            if self.maxAttempts > 1 {
                // Keep an existing retry's original timestamp, delay and attempt budget.
                if !self.pending.values.contains(where: {
                    $0.clientAPIEndpointURL == clientAPIEndpointURL
                        && $0.siteToken == siteToken && $0.body.pushId == body.pushId
                        && $0.body.status == body.status && $0.body.buttonHash == body.buttonHash
                }) {
                    let entry = PendingPushStatus(
                        id: UUID(), body: body, siteToken: siteToken,
                        clientAPIEndpointURL: clientAPIEndpointURL, attempts: 1,
                        nextAttemptAt: Date().addingTimeInterval(max(self.baseDelay, retryAfter ?? 0))
                    )
                    self.save(entry)
                    self.publish(.queued(entry.event, error), siteToken: siteToken)
                    self.publish(.retryScheduled(
                        entry.event, nextAttempt: 2, nextAttemptAt: entry.nextAttemptAt, error: error
                    ), siteToken: siteToken)
                }
                self.scheduleNext()
            }
            completion()
        }
    }

    /// A successful or permanent result for the same status makes its queued retry unnecessary.
    package func discard(
        _ body: PushStatusRequestBody,
        siteToken: String,
        clientAPIEndpointURL: URL = BackendEndpoints().clientAPIEndpointURL,
        result: Result<Void, PushStatusReportingError>,
        completion: @escaping () -> Void
    ) {
        queue.async {
            let ids = self.pending.values.filter {
                $0.clientAPIEndpointURL == clientAPIEndpointURL
                    && $0.siteToken == siteToken && $0.body.pushId == body.pushId
                    && $0.body.status == body.status && $0.body.buttonHash == body.buttonHash
            }.map(\.id)
            for id in ids {
                guard let entry = self.pending[id] else { continue }
                self.remove(id)
                switch result {
                case .success:
                    self.publish(.delivered(entry.event), siteToken: siteToken)
                case .failure(let error):
                    self.publish(.rejected(entry.event, error), siteToken: siteToken)
                }
            }
            self.scheduleNext()
            completion()
        }
    }

    private func scheduleNext() {
        scheduled?.cancel()
        scheduled = nil
        guard !isSending, isNetworkAvailable, session != nil,
              let next = pending.values.min(by: { $0.nextAttemptAt < $1.nextAttemptAt }) else { return }
        let work = DispatchWorkItem { [weak self] in self?.sendNext() }
        scheduled = work
        queue.asyncAfter(deadline: .now() + max(0, next.nextAttemptAt.timeIntervalSinceNow), execute: work)
    }

    private func sendNext() {
        guard !isSending, isNetworkAvailable, let session,
              var entry = pending.values.filter({ $0.nextAttemptAt <= Date() })
                .min(by: { $0.nextAttemptAt < $1.nextAttemptAt }) else {
            scheduleNext()
            return
        }
        guard entry.attempts < maxAttempts else {
            remove(entry.id)
            publish(.dropped(entry.event, attempts: entry.attempts, lastError: nil), siteToken: entry.siteToken)
            scheduleNext()
            return
        }
        isSending = true
        entry.attempts += 1
        // Persist the attempt budget before starting the request.
        entry.nextAttemptAt = Date().addingTimeInterval(baseDelay * pow(2, Double(entry.attempts - 1)))
        save(entry)
        publish(.sending(entry.event, attempt: entry.attempts), siteToken: entry.siteToken)
        let attempted = entry
        PushStatusReporter.send(
            entry.body, siteToken: entry.siteToken,
            clientAPIEndpointURL: entry.clientAPIEndpointURL,
            session: session
        ) { result, retryAfter in
            self.queue.async {
                self.isSending = false
                guard self.pending[attempted.id] != nil else {
                    self.scheduleNext()
                    return
                }
                if case .failure(let error) = result, error.isRetryable, attempted.attempts < self.maxAttempts {
                    var retry = attempted
                    retry.nextAttemptAt = Date().addingTimeInterval(
                        max(self.baseDelay * pow(2, Double(retry.attempts - 1)), retryAfter ?? 0)
                    )
                    self.save(retry)
                    self.publish(.retryScheduled(
                        retry.event, nextAttempt: retry.attempts + 1,
                        nextAttemptAt: retry.nextAttemptAt, error: error
                    ), siteToken: retry.siteToken)
                } else {
                    self.remove(attempted.id)
                    switch result {
                    case .success:
                        self.publish(.delivered(attempted.event), siteToken: attempted.siteToken)
                    case .failure(let error) where error.isRetryable:
                        self.publish(.dropped(
                            attempted.event, attempts: attempted.attempts, lastError: error
                        ), siteToken: attempted.siteToken)
                    case .failure(let error):
                        self.publish(.rejected(attempted.event, error), siteToken: attempted.siteToken)
                    }
                }
                self.scheduleNext()
            }
        }
    }

    private func save(_ entry: PendingPushStatus) {
        pending[entry.id] = entry
        do {
            try storage.save(entry)
        } catch {
            NSLog("RetailCRM push status retry could not be saved: %@", error.localizedDescription)
        }
    }

    private func remove(_ id: UUID) {
        pending.removeValue(forKey: id)
        do {
            try storage.remove(id)
        } catch {
            NSLog("RetailCRM push status retry could not be removed: %@", error.localizedDescription)
        }
    }
}
