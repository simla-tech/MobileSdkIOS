import Core
import Foundation

/// Entry point for tracker events and their delivery state.
public final class Tracker {

    private let config: TrackerConfig
    private let sessionRuntime: SessionRuntime
    private let trackerStateStore = TrackerStateStore()
    private let trackerTimeSyncStore = TrackerTimeSyncStore()
    private let client: TrackerClient
    private let eventQueue: TrackerEventQueue
    private let eventRecordingQueue = DispatchQueue(label: "com.retailcrm.consultant.tracker.record", qos: .utility)
    private var storage: SQLiteTrackerStorage?
    private let stateLock = NSLock()
    private var rateLimitedUntil: Date?
    private var effectiveBatchSize: Int
    private var acceptsEvents = false
    private var startupEvents: [TrackerEvent] = []
    private var canBufferStartupEvents = true
    private var connectedUserToken: String?
    private static let startupEventLimit = 1_000
    private var collectionGeneration: UInt64 = 0
    private var operationTask: Task<Void, Never>?
    private var initializationGeneration: UInt64 = 0
    private var flushTasks: [UUID: Task<Result<Void, TrackerError>, Never>] = [:]
    private var flushAllTasks: [UUID: Task<Void, Never>] = [:]
    private var flushAllProgress: [UUID: TrackerFlushAllProgress] = [:]
    private var periodicFlushTask: Task<Void, Never>?
    private var currentPageContext: TrackerPageContext?
    private var eventUpdateHandler: ((TrackerEventUpdate) -> Void)?
    private var readyUpdateHandler: ((Bool, TrackerError?) -> Void)?
    private var readyResult: Result<Bool, TrackerError>?
    private var readyRevision: UInt64 = 0
    private var deliveredReadyRevision: UInt64?
    private var storageInitializationError: TrackerError?
    private var activeUserToken: String?
    private var needsStorageReset = false

    private var canCollectEvents: Bool {
        stateLock.withLock {
            acceptsEvents && canCollectEventsForCurrentSession
        }
    }

    private var canCollectEventsForCurrentSession: Bool {
        let state = trackerStateStore.currentState
        guard state.consentState != .denied else {
            return false
        }
        guard state.isAvailable else {
            return false
        }
        guard !state.requiresConsent else {
            return state.consentState == .granted
        }
        return true
    }

    private var isRateLimited: Bool {
        guard let rateLimitedUntil else {
            return false
        }
        guard rateLimitedUntil <= Date() else {
            return true
        }
        self.rateLimitedUntil = nil
        return false
    }

    package init(
        config: TrackerConfig,
        sessionRuntime: SessionRuntime,
        storage: SQLiteTrackerStorage? = nil,
        client: TrackerClient? = nil
    ) {
        self.config = config
        self.effectiveBatchSize = min(config.batchSize, 50)
        self.sessionRuntime = sessionRuntime
        self.client = client ?? TrackerClient(sessionRuntime: sessionRuntime)
        self.eventQueue = TrackerEventQueue()
        self.storage = storage
        Task { [weak self, sessionRuntime] in
            guard let self else { return }
            await sessionRuntime.addLifecycleListener(self)
        }
    }

    deinit {
        periodicFlushTask?.cancel()
        operationTask?.cancel()
        flushTasks.values.forEach { $0.cancel() }
        flushAllTasks.values.forEach { $0.cancel() }
    }

    /// Whether tracking requires explicit consent for the connected session.
    package var requiresConsent: Bool { trackerStateStore.currentState.requiresConsent }

    /// Current consent decision. The host application must restore its saved decision after launch.
    public var consentState: TrackerConsentState { trackerStateStore.currentState.consentState }

    package var pendingEventCount: Int { eventQueue.count }

    /// Receives future queue and delivery updates. Callbacks may arrive off the main thread.
    public var onEventUpdate: ((TrackerEventUpdate) -> Void)? {
        get { stateLock.withLock { eventUpdateHandler } }
        set { stateLock.withLock { eventUpdateHandler = newValue } }
    }

    /// Reports preparation on the main thread: whether consent UI is needed and an optional error.
    /// Preparation starts automatically when the shared session connects. Late subscribers receive
    /// the current result; consent changes update the flag. No result is emitted while awaiting connection.
    public var onReadyUpdate: ((Bool, TrackerError?) -> Void)? {
        get { stateLock.withLock { readyUpdateHandler } }
        set {
            stateLock.withLock {
                readyUpdateHandler = newValue
                readyRevision &+= 1
            }
            notifyReadyHandler()
        }
    }

    private func notifyReadyHandler() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let update = self.stateLock.withLock { () -> (((Bool, TrackerError?) -> Void), Result<Bool, TrackerError>)? in
                guard let handler = self.readyUpdateHandler, let result = self.readyResult,
                      self.deliveredReadyRevision != self.readyRevision else { return nil }
                self.deliveredReadyRevision = self.readyRevision
                return (handler, result)
            }
            guard let (handler, result) = update else { return }
            switch result {
            case .success(let requiresForm): handler(requiresForm, nil)
            case .failure(let error): handler(false, error)
            }
        }
    }

    private func publishReadiness(error: TrackerError? = nil, generation: UInt64? = nil) {
        let changed = stateLock.withLock { () -> Bool in
            if let generation, generation != initializationGeneration { return false }
            let state = trackerStateStore.currentState
            let result: Result<Bool, TrackerError> = error.map { .failure($0) }
                ?? .success(state.requiresConsent && state.consentState == .unknown)
            guard readyResult != result else { return false }
            readyResult = result
            readyRevision &+= 1
            return true
        }
        if changed { notifyReadyHandler() }
    }

    /// Sets the user's tracking decision and clears queued events when tracking is denied.
    /// The host application owns persistence of this decision.
    ///
    /// - Parameters:
    ///   - consent: User decision about collection of tracker events.
    @discardableResult
    public func setConsent(_ consent: TrackerConsentState) -> Result<Void, TrackerError> {
        let readyChanged = stateLock.withLock { () -> Bool in
            trackerStateStore.setConsent(consent)
            guard case .success? = readyResult else { return false }
            let state = trackerStateStore.currentState
            let result: Result<Bool, TrackerError> = .success(state.requiresConsent && state.consentState == .unknown)
            guard readyResult != result else { return false }
            readyResult = result
            readyRevision &+= 1
            return true
        }
        defer { if readyChanged { notifyReadyHandler() } }
        if consent == .denied || (requiresConsent && consent != .granted) {
            let (dropped, error) = stateLock.withLock { () -> ([TrackerEvent], TrackerError?) in
                collectionGeneration &+= 1
                flushTasks.values.forEach { $0.cancel() }
                flushAllTasks.values.forEach { $0.cancel() }
                periodicFlushTask?.cancel()
                periodicFlushTask = nil
                let events = eventQueue.snapshot() + startupEvents
                startupEvents.removeAll()
                currentPageContext = nil
                eventQueue.clear()
                do {
                    if let storage, storage.hasActiveScope {
                        try storage.savePendingEvents([])
                        try storage.clearOversizedEvents()
                    }
                    return (events, nil)
                } catch {
                    return (events, error as? TrackerError ?? .storage(error.localizedDescription))
                }
            }
            if let error {
                publish(.retryScheduled(dropped.map(\.id), error))
                return .failure(error)
            }
            if !dropped.isEmpty {
                publish(.dropped(dropped.map(\.id), TrackerLocalization.trackingConsentUnavailable.localized))
            }
        } else {
            startPeriodicFlushIfNeeded()
        }
        return .success(())
    }

    /// Records a page view and returns its accepted event ID (startup buffer or persistent queue).
    public func trackPageView(
        screenURI: String,
        title: String? = nil,
        product: TrackerViewedProduct? = nil,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackPageView(
                screenURI: screenURI, title: title, product: product, code: code,
                completion: completion
            )
        }
    }

    /// Records a click and returns its accepted event ID.
    public func trackClick(
        element: String,
        leaving: Bool = false,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackClick(element: element, leaving: leaving, code: code, completion: completion)
        }
    }

    /// Records registration and returns its accepted event ID.
    public func trackRegister(
        customer: TrackerCustomer,
        createCustomer: Bool = false,
        createCustomerByEmail: Bool = false,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackRegister(
                customer: customer, createCustomer: createCustomer,
                createCustomerByEmail: createCustomerByEmail, code: code,
                completion: completion
            )
        }
    }

    /// Records a login and returns its accepted event ID.
    public func trackLogin(
        customerEmail: String,
        subscriptions: [TrackerSubscription] = [],
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackLogin(
                customerEmail: customerEmail, subscriptions: subscriptions, code: code,
                completion: completion
            )
        }
    }

    /// Records a consultant contact and returns its accepted event ID.
    public func trackConsult(
        customerEmail: String,
        subscriptions: [TrackerSubscription] = [],
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackConsult(
                customerEmail: customerEmail, subscriptions: subscriptions, code: code,
                completion: completion
            )
        }
    }

    /// Records a cart opening and returns its accepted event ID.
    public func trackOpenCart(
        customerEmail: String? = nil,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackOpenCart(customerEmail: customerEmail, code: code, completion: completion)
        }
    }

    /// Records a cart change and returns its accepted event ID.
    public func trackCart(
        cartID: String,
        items: [TrackerCartItem] = [],
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackCart(cartID: cartID, items: items, code: code, completion: completion)
        }
    }

    /// Records a contact request and returns its accepted event ID.
    public func trackContact(
        channel: TrackerContactChannel,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackContact(channel: channel, code: code, completion: completion)
        }
    }

    /// Records an order and returns its accepted event ID.
    public func trackOrder(
        identifier: TrackerOrderIdentifier,
        cartID: String? = nil,
        items: [TrackerCartItem] = [],
        deliveryPrice: Double? = nil,
        total: Double? = nil,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackOrder(
                identifier: identifier, cartID: cartID, items: items,
                deliveryPrice: deliveryPrice, total: total, code: code,
                completion: completion
            )
        }
    }

    /// Records a subscription change and returns its accepted event ID.
    public func trackSubscription(
        _ subscription: TrackerSubscription,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackSubscription(subscription, code: code, completion: completion)
        }
    }

    /// Records a form start and returns its accepted event ID.
    public func trackFormStart(
        formSelector: String,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackFormStart(formSelector: formSelector, code: code, completion: completion)
        }
    }

    /// Records a form submission and returns its accepted event ID.
    public func trackFormSubmit(
        formSelector: String,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackFormSubmit(formSelector: formSelector, code: code, completion: completion)
        }
    }

    /// Records a file download and returns its accepted event ID.
    public func trackFileDownload(
        fileName: String,
        element: String? = nil,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackFileDownload(
                fileName: fileName, element: element, code: code,
                completion: completion
            )
        }
    }

    /// Records a favorite product change and returns its accepted event ID.
    public func trackFavoriteProduct(
        offer: TrackerOfferIdentifier,
        removed: Bool = false,
        code: String? = nil
    ) async throws -> String {
        try await awaitCompletion { completion in
            trackFavoriteProduct(
                offer: offer, removed: removed, code: code,
                completion: completion
            )
        }
    }

    /// Attempts to send all events in the current queue snapshot.
    public func flushAll() async throws {
        try await awaitCompletion { completion in
            flushAll(completion: completion)
        }
    }

    private func awaitCompletion<Value: Sendable>(
        _ register: (@escaping (Result<Value, TrackerError>) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            register { result in
                continuation.resume(with: result)
            }
        }
    }

}

/// Completion-based tracker API.
public extension Tracker {

    /// Records a page view and uses its absolute URI as the context for later events.
    ///
    /// - Parameters:
    ///   - screenURI: Absolute URI of the screen where the event occurred.
    ///   - title: Optional screen title.
    ///   - product: Optional product details associated with the page view.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackPageView(
        screenURI: String,
        title: String? = nil,
        product: TrackerViewedProduct? = nil,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueRecord(
            { [self] in
                return record(.pageView, code: code) {
                    let uri = try TrackerEventDataFactory.absoluteURI(screenURI, name: "screenURI")
                    let data = try TrackerEventDataFactory.pageView(product)
                    let previous = stateLock.withLock { currentPageContext }
                    let context = TrackerPageContext(
                        pageURL: uri, pageTitle: title, referrerURL: previous?.pageURL
                    )
                    return (data, context)
                }
            },
            completion: completion
        )
    }

    /// Records a click on the element identified by `element`.
    ///
    /// - Parameters:
    ///   - element: Identifier of the clicked UI element.
    ///   - leaving: Whether the click leaves the current screen.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackClick(
        element: String,
        leaving: Bool = false,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .click,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.click(element: element, leaving: leaving), nil)
            },
            completion: completion
        )
    }

    /// Records registration. Set `createCustomer` to request CRM customer creation.
    /// Use `createCustomerByEmail` with it when no site customer ID is available.
    ///
    /// - Parameters:
    ///   - customer: Customer attributes to include in the registration event.
    ///   - createCustomer: Whether to request creation of a CRM customer.
    ///   - createCustomerByEmail: Whether to create that CRM customer by email when no site customer ID exists.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackRegister(
        customer: TrackerCustomer,
        createCustomer: Bool = false,
        createCustomerByEmail: Bool = false,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .register,
            code: code,
            createCustomer: createCustomer,
            createCustomerByEmail: createCustomerByEmail,
            makeData: {
                (try TrackerEventDataFactory.register(customer: customer), nil)
            },
            completion: completion
        )
    }

    /// Records a customer login using the supplied email address.
    ///
    /// - Parameters:
    ///   - customerEmail: Email address of the customer associated with the event.
    ///   - subscriptions: Subscription states associated with this customer event.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackLogin(
        customerEmail: String,
        subscriptions: [TrackerSubscription] = [],
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .login,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.customerEmail(customerEmail, subscriptions: subscriptions), nil)
            },
            completion: completion
        )
    }

    /// Records an attempt to contact a consultant.
    ///
    /// - Parameters:
    ///   - customerEmail: Email address of the customer associated with the event.
    ///   - subscriptions: Subscription states associated with this customer event.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackConsult(
        customerEmail: String,
        subscriptions: [TrackerSubscription] = [],
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .consult,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.customerEmail(customerEmail, subscriptions: subscriptions), nil)
            },
            completion: completion
        )
    }

    /// Records a cart opening, optionally with the customer's email address.
    ///
    /// - Parameters:
    ///   - customerEmail: Email address of the customer associated with the event.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackOpenCart(
        customerEmail: String? = nil,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .openCart,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.openCart(customerEmail: customerEmail), nil)
            },
            completion: completion
        )
    }

    /// Records the current cart contents after a cart change.
    ///
    /// - Parameters:
    ///   - cartID: Cart identifier associated with the event.
    ///   - items: Offers and quantities in the cart or order.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackCart(
        cartID: String,
        items: [TrackerCartItem] = [],
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .cart,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.cart(id: cartID, items: items), nil)
            },
            completion: completion
        )
    }

    /// Records a contact request through the selected channel.
    ///
    /// - Parameters:
    ///   - channel: Channel through which the customer requested contact.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackContact(
        channel: TrackerContactChannel,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .contact,
            code: code,
            makeData: {
                (TrackerEventDataFactory.contact(channel), nil)
            },
            completion: completion
        )
    }

    /// Records an order with its identifier and optional cart and price details.
    ///
    /// - Parameters:
    ///   - identifier: External order ID or order number.
    ///   - cartID: Cart identifier associated with the event.
    ///   - items: Offers and quantities in the cart or order.
    ///   - deliveryPrice: Delivery cost associated with the order.
    ///   - total: Order total.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackOrder(
        identifier: TrackerOrderIdentifier,
        cartID: String? = nil,
        items: [TrackerCartItem] = [],
        deliveryPrice: Double? = nil,
        total: Double? = nil,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .order,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.order(identifier: identifier, cartID: cartID, items: items, deliveryPrice: deliveryPrice, total: total), nil)
            },
            completion: completion
        )
    }

    /// Records a subscription change, including its active state.
    ///
    /// - Parameters:
    ///   - subscription: Subscription and its active state.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackSubscription(
        _ subscription: TrackerSubscription,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .subscription,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.subscription(subscription), nil)
            },
            completion: completion
        )
    }

    /// Records the start of filling a form identified by `formSelector`.
    ///
    /// - Parameters:
    ///   - formSelector: Identifier of the form in the application.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackFormStart(
        formSelector: String,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .formStart,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.form(formSelector), nil)
            },
            completion: completion
        )
    }

    /// Records submission of a form identified by `formSelector`.
    ///
    /// - Parameters:
    ///   - formSelector: Identifier of the form in the application.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackFormSubmit(
        formSelector: String,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .formSubmit,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.form(formSelector), nil)
            },
            completion: completion
        )
    }

    /// Records a file download and its optional source element.
    ///
    /// - Parameters:
    ///   - fileName: Name of the downloaded file.
    ///   - element: Optional identifier of the element that initiated the download.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackFileDownload(
        fileName: String,
        element: String? = nil,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .fileDownload,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.fileDownload(fileName: fileName, element: element), nil)
            },
            completion: completion
        )
    }

    /// Records adding or removing an offer from favorites.
    ///
    /// - Parameters:
    ///   - offer: Offer identifier associated with the event.
    ///   - removed: Whether the offer was removed from favorites.
    ///   - code: Optional event code configured for the iOS platform.
    ///   - completion: Receives the accepted event ID or a tracker error on the main thread.
    func trackFavoriteProduct(
        offer: TrackerOfferIdentifier,
        removed: Bool = false,
        code: String? = nil,
        completion: @escaping (Result<String, TrackerError>) -> Void = { _ in }
    ) {
        enqueueTrack(
            .favoriteProduct,
            code: code,
            makeData: {
                (try TrackerEventDataFactory.favoriteProduct(offer: offer, removed: removed), nil)
            },
            completion: completion
        )
    }

    /// Attempts all events in the current queue snapshot without bypassing consent or rate limits.
    /// The completion runs once on the main actor; partial delivery reports remaining IDs in `.flushIncomplete`.
    ///
    /// - Parameters:
    ///   - completion: Receives the flush result on the main actor; partial delivery reports remaining event IDs.
    func flushAll(
        completion: @escaping (Result<Void, TrackerError>) -> Void = { _ in }
    ) {
        eventRecordingQueue.async { [self] in
            let id = UUID()
            stateLock.withLock {
                let snapshot = eventQueue.snapshot()
                flushAllProgress[id] = TrackerFlushAllProgress(eventIDs: Set(snapshot.map(\.id)))
                let previousTask = operationTask
                let task = Task { [weak self] in
                    await previousTask?.value
                    let result: Result<Void, TrackerError>
                    if let self {
                        result = await self.performFlushAll(snapshot: snapshot, requestID: id)
                    } else {
                        result = .failure(.unavailable)
                    }
                    self?.stateLock.withLock {
                        self?.flushAllProgress.removeValue(forKey: id)
                        self?.flushAllTasks.removeValue(forKey: id)
                    }
                    await MainActor.run { completion(result) }
                }
                flushAllTasks[id] = task
                operationTask = task
            }
        }
    }
}

package extension Tracker {

    /// Sends one pending batch during automatic queue processing.
    @discardableResult
    func flush() async -> Result<Void, TrackerError> {
        let id = UUID()
        let task = stateLock.withLock { () -> Task<Result<Void, TrackerError>, Never> in
            let previousTask = operationTask
            let task = Task<Result<Void, TrackerError>, Never> { [weak self] in
                await previousTask?.value
                guard let self, !Task.isCancelled else { return .failure(TrackerError.unavailable) }
                return await self.performFlush()
            }
            operationTask = Task { _ = await task.value }
            flushTasks[id] = task
            return task
        }
        let result = await task.value
        _ = stateLock.withLock { flushTasks.removeValue(forKey: id) }
        return result
    }
}

private struct TrackerFlushBatchOutcome {
    let failedIDs: Set<String>
    let error: TrackerError?
    let blocked: Bool

    static func blocked(_ events: [TrackerEvent], error: TrackerError) -> Self {
        Self(failedIDs: Set(events.map(\.id)), error: error, blocked: true)
    }
}

private struct TrackerFlushAllProgress {
    let eventIDs: Set<String>
    var deliveredIDs: Set<String> = []
    var terminalIDs: Set<String> = []
}

private extension Tracker {

    func performFlush() async -> Result<Void, TrackerError> {
        guard stateLock.withLock({ acceptsEvents }) else {
            return .failure(storageInitializationError ?? .missingConnection)
        }
        guard canCollectEvents else {
            return .failure(requiresConsent && consentState != .granted ? .consentRequired : .unavailable)
        }
        guard !isRateLimited else {
            return .failure(.httpStatus(429, [], retryAfter: rateLimitedUntil?.timeIntervalSinceNow))
        }

        await refreshTimeSyncIfNeeded()
        guard !isRateLimited else {
            return .failure(.httpStatus(429, [], retryAfter: rateLimitedUntil?.timeIntervalSinceNow))
        }

        let (events, generation, userToken): ([TrackerEvent], UInt64, String?) = stateLock.withLock {
            guard acceptsEvents, canCollectEventsForCurrentSession else {
                return ([], collectionGeneration, nil)
            }
            return (
                Array(eventQueue.snapshot().prefix(effectiveBatchSize)),
                collectionGeneration,
                activeUserToken
            )
        }
        guard !events.isEmpty else {
            return .success(())
        }
        guard let userToken else { return .failure(.missingConnection) }
        let outcome = await sendBatch(events, generation: generation, userToken: userToken)
        guard !outcome.failedIDs.isEmpty else { return .success(()) }
        return .failure(outcome.error ?? .flushIncomplete(outcome.failedIDs.sorted()))
    }

    func performFlushAll(
        snapshot: [TrackerEvent],
        requestID: UUID
    ) async -> Result<Void, TrackerError> {
        let (ready, userToken, initializationError) = stateLock.withLock {
            (acceptsEvents && canCollectEventsForCurrentSession, activeUserToken, storageInitializationError)
        }
        guard ready, userToken != nil, !Task.isCancelled else {
            if requiresConsent && consentState != .granted { return .failure(.consentRequired) }
            return .failure(initializationError ?? (userToken == nil ? .missingConnection : .unavailable))
        }
        guard !isRateLimited else {
            return .failure(.httpStatus(429, [], retryAfter: rateLimitedUntil?.timeIntervalSinceNow))
        }

        let oversizedIDs: [String]
        do {
            oversizedIDs = try stateLock.withLock {
                try storage?.loadOversizedEventIDs() ?? []
            }
        } catch {
            return .failure(.storage(error.localizedDescription))
        }
        var offset = 0

        while offset < snapshot.count {
            let (generation, userToken, batchSize, ready) = stateLock.withLock {
                (collectionGeneration, activeUserToken, effectiveBatchSize, acceptsEvents && canCollectEventsForCurrentSession)
            }
            guard ready, let userToken, !Task.isCancelled else {
                break
            }
            if isRateLimited {
                break
            }

            let end = min(snapshot.count, offset + max(1, batchSize))
            let batch = Array(snapshot[offset..<end])
            offset = end
            let (queuedIDs, progress) = stateLock.withLock {
                (Set(eventQueue.snapshot().map(\.id)), flushAllProgress[requestID])
            }
            let present = batch.filter {
                queuedIDs.contains($0.id) &&
                    progress?.deliveredIDs.contains($0.id) != true &&
                    progress?.terminalIDs.contains($0.id) != true
            }
            guard !present.isEmpty else { continue }

            await refreshTimeSyncIfNeeded()
            let outcome = await sendBatch(present, generation: generation, userToken: userToken)
            if outcome.blocked {
                break
            }
        }

        let deliveredIDs = stateLock.withLock {
            flushAllProgress[requestID]?.deliveredIDs ?? []
        }
        let failedIDs = Set(snapshot.map(\.id)).subtracting(deliveredIDs).union(oversizedIDs)
        return failedIDs.isEmpty ? .success(()) : .failure(.flushIncomplete(failedIDs.sorted()))
    }

    func sendBatch(
        _ events: [TrackerEvent],
        generation: UInt64,
        userToken: String
    ) async -> TrackerFlushBatchOutcome {
        guard !events.isEmpty else {
            return TrackerFlushBatchOutcome(failedIDs: [], error: nil, blocked: false)
        }
        guard isCurrentCollection(generation, userToken: userToken), !Task.isCancelled else {
            return .blocked(events, error: .unavailable)
        }
        guard !isRateLimited else {
            return .blocked(
                events,
                error: .httpStatus(429, [], retryAfter: rateLimitedUntil?.timeIntervalSinceNow)
            )
        }

        let customer = trackerStateStore.currentState
        let outgoing = events.map {
            $0.attributedIfAnonymous(
                systemCustomerID: customer.systemCustomerID,
                systemCustomerExternalID: customer.siteCustomerID
            )
        }
        do {
            let batches = try TrackerBatchBuilder.batches(outgoing)
            if batches.count > 1 {
                return await sendBatches(batches, generation: generation, userToken: userToken)
            }
            if events.count == 1 {
                let size = try JSONEncoder().encode(outgoing).count
                if size > TrackerBatchBuilder.requestLimit {
                    return quarantineOversizedEvent(
                        events[0], error: .eventTooLarge(sizeBytes: size, limitBytes: TrackerBatchBuilder.requestLimit),
                        generation: generation, userToken: userToken
                    )
                }
            }
        } catch {
            let failure = TrackerError.requestEncodingFailed(error.localizedDescription)
            publish(.retryScheduled(events.map(\.id), failure))
            return TrackerFlushBatchOutcome(failedIDs: Set(events.map(\.id)), error: failure, blocked: false)
        }

        let batchIDs = events.map(\.id)
        do {
            let response = try await client.send(events: outgoing, expectedUserToken: userToken) { [self] payload in
                publish(.sending(batchIDs, payload: payload))
            }
            guard isCurrentCollection(generation, userToken: userToken), !Task.isCancelled else {
                return .blocked(events, error: .unavailable)
            }
            let attemptedIDs = Set(batchIDs)
            let failures = response.failures(attemptedEventIDs: attemptedIDs)
            let rejectedIDs = Set(failures.rejectedReasons.keys)
            let deliveredIDs = attemptedIDs.subtracting(failures.retryableIDs).subtracting(rejectedIDs)
            do {
                try removePersistedEvents(ids: deliveredIDs.union(rejectedIDs))
            } catch {
                let failure = TrackerError.storage(error.localizedDescription)
                publish(.retryScheduled(batchIDs, failure))
                return TrackerFlushBatchOutcome(failedIDs: attemptedIDs, error: failure, blocked: false)
            }
            if !deliveredIDs.isEmpty {
                publish(.delivered(batchIDs.filter(deliveredIDs.contains)))
            }
            for event in events {
                if let reason = failures.rejectedReasons[event.id] {
                    publish(.rejected(event.id, .eventRejected(reason)))
                }
            }
            if !failures.retryableIDs.isEmpty {
                publish(.retryScheduled(
                    batchIDs.filter(failures.retryableIDs.contains),
                    .requestFailed(TrackerLocalization.serverRetry.localized)
                ))
            }
            let failedIDs = failures.retryableIDs.union(rejectedIDs)
            return TrackerFlushBatchOutcome(
                failedIDs: failedIDs,
                error: failedIDs.isEmpty ? nil : .flushIncomplete(failedIDs.sorted()),
                blocked: false
            )
        } catch let error as TrackerClientError {
            let trackerError = error.asTrackerError
            if case .httpStatus(413, _, _) = trackerError {
                // The server may enforce a lower limit; isolate whole events without guessing it.
                if events.count > 1 {
                    return await sendBatches(events.map { [$0] }, generation: generation, userToken: userToken)
                }
                return quarantineOversizedEvent(
                    events[0], error: .eventRejected(trackerError.localizedDescription),
                    generation: generation, userToken: userToken
                )
            }
            applyRateLimit(error: error)
            publish(.retryScheduled(batchIDs, trackerError))
            let blocked: Bool
            if case let .httpStatus(status, _, _) = trackerError {
                blocked = status == 401 || status == 403 || status == 429
            } else {
                blocked = false
            }
            return TrackerFlushBatchOutcome(failedIDs: Set(batchIDs), error: trackerError, blocked: blocked)
        } catch let error as TrackerError {
            publish(.retryScheduled(batchIDs, error))
            let blocked: Bool
            if case .missingConnection = error {
                blocked = true
            } else {
                blocked = false
            }
            return TrackerFlushBatchOutcome(failedIDs: Set(batchIDs), error: error, blocked: blocked)
        } catch is CancellationError {
            return .blocked(events, error: .unavailable)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            let trackerError = TrackerError.requestFailed(error.localizedDescription)
            publish(.retryScheduled(batchIDs, trackerError))
            return .blocked(events, error: trackerError)
        } catch {
            let trackerError = TrackerError.requestFailed(error.localizedDescription)
            publish(.retryScheduled(batchIDs, trackerError))
            return TrackerFlushBatchOutcome(failedIDs: Set(batchIDs), error: trackerError, blocked: false)
        }
    }

    func sendBatches(
        _ batches: [[TrackerEvent]],
        generation: UInt64,
        userToken: String
    ) async -> TrackerFlushBatchOutcome {
        var failedIDs = Set<String>()
        var firstError: TrackerError?
        for (index, batch) in batches.enumerated() {
            let outcome = await sendBatch(batch, generation: generation, userToken: userToken)
            failedIDs.formUnion(outcome.failedIDs)
            firstError = firstError ?? outcome.error
            if outcome.blocked {
                failedIDs.formUnion(batches.dropFirst(index + 1).flatMap { $0.map(\.id) })
                return TrackerFlushBatchOutcome(failedIDs: failedIDs, error: firstError, blocked: true)
            }
        }
        return TrackerFlushBatchOutcome(failedIDs: failedIDs, error: firstError, blocked: false)
    }

    func quarantineOversizedEvent(
        _ event: TrackerEvent,
        error failure: TrackerError,
        generation: UInt64,
        userToken: String
    ) -> TrackerFlushBatchOutcome {
        do {
            try stateLock.withLock {
                guard collectionGeneration == generation,
                      acceptsEvents,
                      activeUserToken == userToken,
                      canCollectEventsForCurrentSession,
                      let storage else {
                    throw TrackerError.unavailable
                }
                try storage.moveToOversized(event)
                eventQueue.remove(ids: [event.id])
            }
            publish(.rejected(event.id, failure))
            return TrackerFlushBatchOutcome(failedIDs: [event.id], error: failure, blocked: false)
        } catch {
            let trackerError = (error as? TrackerError) ?? .storage(error.localizedDescription)
            publish(.retryScheduled([event.id], trackerError))
            return TrackerFlushBatchOutcome(
                failedIDs: [event.id],
                error: trackerError,
                blocked: trackerError == .unavailable
            )
        }
    }

    func enqueueInitialization(userToken: String) -> Task<Result<Void, TrackerError>, Never> {
        stateLock.withLock {
            storageInitializationError = nil
            let previousTask = operationTask
            initializationGeneration &+= 1
            let generation = initializationGeneration
            let task = Task { [weak self] () -> Result<Void, TrackerError> in
                await previousTask?.value
                guard let self else { return .failure(.unavailable) }
                return self.eventRecordingQueue.sync {
                    self.performStart(userToken: userToken, generation: generation)
                }
            }
            operationTask = Task { [weak self] in
                guard case .success = await task.value, let self else { return }
                self.startPeriodicFlushIfNeeded()
                _ = await self.performFlush()
            }
            return task
        }
    }

    func performStart(userToken: String, generation: UInt64) -> Result<Void, TrackerError> {
        if stateLock.withLock({ storage == nil }) {
            do {
                let newStorage = try SQLiteTrackerStorage()
                stateLock.withLock {
                    storage = newStorage
                    storageInitializationError = nil
                }
            } catch {
                stateLock.withLock {
                    storageInitializationError = .storage(error.localizedDescription)
                }
            }
        }
        var startupDropped: [TrackerEvent] = []
        let error = stateLock.withLock { () -> TrackerError? in
            guard initializationGeneration == generation else { return .unavailable }
            if !canCollectEventsForCurrentSession {
                startupDropped = startupEvents
                startupEvents.removeAll()
                canBufferStartupEvents = false
                currentPageContext = nil
            }
            do {
                if needsStorageReset {
                    guard let storage else {
                        throw storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized)
                    }
                    try storage.clearForIdentityChange()
                    needsStorageReset = false
                }
                if try activateStorageScope(userToken: userToken) {
                    rateLimitedUntil = nil
                    effectiveBatchSize = min(config.batchSize, 50)
                }
                if requiresConsent && consentState != .granted || consentState == .denied {
                    guard let storage else {
                        throw storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized)
                    }
                    try storage.savePendingEvents([])
                    try storage.clearOversizedEvents()
                    eventQueue.clear()
                } else {
                    try restorePendingEventsLocked()
                }
                if !startupEvents.isEmpty {
                    guard let storage else {
                        throw storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized)
                    }
                    let customer = trackerStateStore.currentState
                    let buffered = startupEvents.map {
                        $0.attributedIfAnonymous(
                            systemCustomerID: customer.systemCustomerID,
                            systemCustomerExternalID: customer.siteCustomerID
                        )
                    }
                    let combined = eventQueue.snapshot() + buffered
                    let retained = Array(combined.suffix(Self.startupEventLimit))
                    try storage.savePendingEvents(retained)
                    startupDropped = Array(combined.dropLast(retained.count))
                    eventQueue.clear()
                    eventQueue.prepend(retained)
                }
                startupEvents.removeAll()
                canBufferStartupEvents = false
            } catch {
                acceptsEvents = false
                storageInitializationError = error as? TrackerError ?? .storage(error.localizedDescription)
                return storageInitializationError
            }
            storageInitializationError = nil
            acceptsEvents = true
            activeUserToken = userToken
            return nil
        }
        if !startupDropped.isEmpty {
            publish(.dropped(startupDropped.map(\.id), canCollectEvents
                ? TrackerLocalization.queueCapacityExceeded.localized
                : TrackerLocalization.trackingConsentUnavailable.localized))
        }
        if let error {
            publish(.retryScheduled([], error))
            publishReadiness(error: error, generation: generation)
            return .failure(error)
        }
        publishReadiness(generation: generation)
        return .success(())
    }

    func performDisconnect() {
        stateLock.withLock {
            eventQueue.clear()
            activeUserToken = nil
            currentPageContext = nil
            rateLimitedUntil = nil
        }
    }

    func activateStorageScope(userToken: String) throws -> Bool {
        guard !userToken.isEmpty else {
            return false
        }
        return try storage?.activateScope(
            siteToken: sessionRuntime.config.siteToken,
            userToken: userToken
        ) ?? false
    }

    func restorePendingEventsLocked() throws {
        guard let storage else { throw storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized) }
        let events = try storage.loadPendingEvents()
        eventQueue.clear()
        let dropped = eventQueue.prepend(events)
        if !dropped.isEmpty {
            try storage.savePendingEvents(eventQueue.snapshot())
        }
    }

    func applyRateLimit(error: TrackerClientError) {
        guard let retryAfter = error.rateLimitRetryAfter, retryAfter > 0 else {
            return
        }

        let until = Date().addingTimeInterval(retryAfter)
        guard let currentRateLimitedUntil = rateLimitedUntil else {
            rateLimitedUntil = until
            return
        }

        if currentRateLimitedUntil < until {
            rateLimitedUntil = until
        }
    }

    func enqueueTrack(
        _ type: TrackerEventName,
        code: String?,
        createCustomer: Bool? = nil,
        createCustomerByEmail: Bool? = nil,
        makeData: @escaping () throws -> ([String: TrackerEventDataValue]?, TrackerPageContext?),
        completion: @escaping (Result<String, TrackerError>) -> Void
    ) {
        let utm = type == .order ? CrmUtmAttributionStorage.shared.load() : nil
        enqueueRecord({ [self] in
            record(
                type,
                code: code,
                createCustomer: createCustomer,
                createCustomerByEmail: createCustomerByEmail,
                utm: utm,
                makeData: makeData
            )
        }, completion: completion)
    }

    func enqueueRecord(
        _ operation: @escaping () -> Result<String, TrackerError>,
        completion: @escaping (Result<String, TrackerError>) -> Void
    ) {
        eventRecordingQueue.async {
            let result = operation()
            DispatchQueue.main.async { completion(result) }
        }
    }

    func record(
        _ type: TrackerEventName,
        code: String?,
        createCustomer: Bool? = nil,
        createCustomerByEmail: Bool? = nil,
        utm: CrmUtmAttribution? = nil,
        makeData: () throws -> ([String: TrackerEventDataValue]?, TrackerPageContext?)
    ) -> Result<String, TrackerError> {
        do {
            let normalizedCode = try TrackerEventDataFactory.code(code)
            let (data, explicitContext) = try makeData()
            return enqueueEvent(
                type: type,
                data: data,
                code: normalizedCode,
                createCustomer: createCustomer,
                createCustomerByEmail: createCustomerByEmail,
                utm: utm,
                pageContext: explicitContext
            )
        } catch let error as TrackerError {
            return .failure(error)
        } catch {
            return .failure(.invalidEvent(error.localizedDescription))
        }
    }

    func enqueueEvent(
        type: TrackerEventName,
        data: [String: TrackerEventDataValue]?,
        code: String?,
        createCustomer: Bool?,
        createCustomerByEmail: Bool?,
        utm: CrmUtmAttribution? = nil,
        pageContext: TrackerPageContext?
    ) -> Result<String, TrackerError> {
        let context = pageContext ?? stateLock.withLock { currentPageContext }
        let customer = trackerStateStore.currentState
        let event = TrackerEvent(
            type: type.rawValue,
            code: code,
            data: data,
            pageURL: context?.pageURL,
            pageTitle: context?.pageTitle,
            referrerURL: context?.referrerURL,
            timestamp: TrackerEventTimestamp.make(trackerTimeSyncStore.resolvedServerDate()),
            createCustomer: createCustomer,
            createCustomerByEmail: createCustomerByEmail,
            systemCustomerID: customer.systemCustomerID,
            systemCustomerExternalID: customer.siteCustomerID,
            utm: utm
        )

        let outcome = stateLock.withLock { () -> Result<([TrackerEvent], Bool), TrackerError> in
            guard acceptsEvents else {
                guard consentState != .denied else { return .failure(.consentRequired) }
                guard canBufferStartupEvents else { return .failure(.missingConnection) }
                startupEvents.append(event)
                let overflow = max(0, startupEvents.count - Self.startupEventLimit)
                let dropped = Array(startupEvents.prefix(overflow))
                startupEvents.removeFirst(overflow)
                if let pageContext { currentPageContext = pageContext }
                return .success((dropped, false))
            }
            guard canCollectEventsForCurrentSession else {
                return .failure(requiresConsent && consentState != .granted ? .consentRequired : .unavailable)
            }
            guard let storage else {
                return .failure(storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized))
            }
            let previousEvents = eventQueue.snapshot()
            let dropped = eventQueue.append(event)
            do {
                try storage.appendPendingEvent(event, dropping: Set(dropped.map(\.id)))
            } catch {
                eventQueue.clear()
                eventQueue.prepend(previousEvents)
                return .failure(.storage(error.localizedDescription))
            }
            if let pageContext { currentPageContext = pageContext }
            return .success((dropped, eventQueue.count >= effectiveBatchSize))
        }
        switch outcome {
        case let .failure(error):
            return .failure(error)
        case let .success((dropped, shouldFlush)):
            publish(.queued([event.id]))
            if !dropped.isEmpty {
                publish(.dropped(dropped.map(\.id), TrackerLocalization.queueCapacityExceeded.localized))
            }
            if shouldFlush {
                Task { [weak self] in
                    _ = await self?.flush()
                }
            }
            return .success(event.id)
        }
    }

    func publish(_ update: TrackerEventUpdate) {
        let handler = stateLock.withLock { () -> ((TrackerEventUpdate) -> Void)? in
            let deliveredIDs: Set<String>
            let terminalIDs: Set<String>
            switch update {
            case let .delivered(ids):
                deliveredIDs = Set(ids)
                terminalIDs = []
            case let .rejected(id, _):
                deliveredIDs = []
                terminalIDs = [id]
            case let .dropped(ids, _):
                deliveredIDs = []
                terminalIDs = Set(ids)
            default:
                deliveredIDs = []
                terminalIDs = []
            }
            if !deliveredIDs.isEmpty || !terminalIDs.isEmpty {
                for id in Array(flushAllProgress.keys) {
                    guard var progress = flushAllProgress[id] else { continue }
                    progress.deliveredIDs.formUnion(deliveredIDs.intersection(progress.eventIDs))
                    progress.terminalIDs.formUnion(terminalIDs.intersection(progress.eventIDs))
                    flushAllProgress[id] = progress
                }
            }
            return eventUpdateHandler
        }
        handler?(update)
    }

    func removePersistedEvents(ids: Set<String>) throws {
        try stateLock.withLock {
            guard let storage else { throw storageInitializationError ?? .storage(TrackerLocalization.storageUnavailable.localized) }
            try storage.removePendingEvents(ids: ids)
            eventQueue.remove(ids: ids)
        }
    }

    @discardableResult
    func enqueueOperation(
        _ operation: @escaping (Tracker) async -> Void
    ) -> Task<Void, Never> {
        stateLock.withLock {
            let previousTask = operationTask
            let task = Task { [weak self] in
                await previousTask?.value
                guard let self, !Task.isCancelled else {
                    return
                }
                await operation(self)
            }
            operationTask = task
            return task
        }
    }

    func pauseEventCollection() {
        stateLock.withLock {
            readyResult = nil
            readyRevision &+= 1
            acceptsEvents = false
            activeUserToken = nil
            collectionGeneration &+= 1
            flushAllTasks.values.forEach { $0.cancel() }
            periodicFlushTask?.cancel()
            periodicFlushTask = nil
        }
    }

    func isCurrentCollection(_ generation: UInt64, userToken: String) -> Bool {
        stateLock.withLock {
            generation == collectionGeneration &&
                activeUserToken == userToken &&
                acceptsEvents &&
                canCollectEventsForCurrentSession
        }
    }

    func refreshTimeSyncIfNeeded() async {
        guard
            !Task.isCancelled,
            !isRateLimited,
            trackerTimeSyncStore.shouldRefresh(interval: config.timeSyncInterval)
        else {
            return
        }

        do {
            let timestamp = try await client.fetchServerTime()
            trackerTimeSyncStore.setServerTimestamp(timestamp)
        } catch let error as TrackerClientError {
            applyRateLimit(error: error)
        } catch {
            return
        }
    }

    func startPeriodicFlushIfNeeded() {
        stateLock.withLock {
            guard
                acceptsEvents,
                canCollectEventsForCurrentSession,
                config.flushInterval > 0,
                periodicFlushTask == nil
            else {
                return
            }

            periodicFlushTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let flushInterval = self?.config.flushInterval else {
                        return
                    }

                    do {
                        let nanoseconds = UInt64((flushInterval * 1_000_000_000).rounded())
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }

                    await self?.flush()
                }
            }
        }
    }
}

package extension Tracker {

    /// Records a recommendation view using the normal tracker queue.
    func trackRecommendationImpression(
        executionID: UInt64,
        screenURI: String,
        title: String?,
        completion: @escaping (Result<String, TrackerError>) -> Void
    ) {
        enqueueRecord(
            { [self] in
                return record(.pageView, code: nil) {
                    guard executionID > 0 else {
                        throw TrackerError.invalidEvent("recommendation execution ID must be greater than zero")
                    }
                    let uri = try TrackerEventDataFactory.absoluteURI(screenURI, name: "screenURI")
                    let previous = stateLock.withLock { currentPageContext }
                    let context = TrackerPageContext(
                        pageURL: uri, pageTitle: title, referrerURL: previous?.pageURL
                    )
                    return (["recommendation_execution_id": .uint64(executionID)], context)
                }
            },
            completion: completion
        )
    }

    /// Records a recommendation product click using the normal tracker queue.
    func trackRecommendationClick(
        executionID: UInt64,
        productID: Int64,
        position: Int?,
        element: String?,
        leaving: Bool,
        completion: @escaping (Result<String, TrackerError>) -> Void
    ) {
        enqueueTrack(.click, code: nil, makeData: {
            guard executionID > 0, productID > 0, productID <= Int64(UInt32.max) else {
                throw TrackerError.invalidEvent("invalid recommendation click identifiers")
            }
            if let position, !(0...Int(UInt32.max)).contains(position) {
                throw TrackerError.invalidEvent("invalid recommendation position")
            }
            var data: [String: TrackerEventDataValue] = [
                "recommendation_execution_id": .uint64(executionID),
                "product_id": .int(Int(productID)),
                "leaving": .bool(leaving)
            ]
            if let position { data["recommendation_position"] = .int(position) }
            if let element = element?.trimmingCharacters(in: .whitespacesAndNewlines), !element.isEmpty {
                data["el"] = .string(element)
            }
            return (data, nil)
        }, completion: completion)
    }

}

extension Tracker: SessionLifecycleListener {

    package func sessionDidFailToConnect(_ error: CoreError) {
        eventRecordingQueue.sync {
            pauseEventCollection()
            stateLock.withLock {
                initializationGeneration &+= 1
            }
            publishReadiness(error: TrackerError.from(error))
        }
    }

    package func sessionDidConnect(
        credentials: SessionCredentials,
        pageContext: ConnectPageContext,
        user: ConnectUser,
        response: ConnectResponse,
        customerIdentity: CrmSdkCustomerIdentity?
    ) {
        eventRecordingQueue.sync {
            handleSessionConnect(
                credentials: credentials, pageContext: pageContext, response: response,
                customerIdentity: customerIdentity
            )
        }
    }

    private func handleSessionConnect(
        credentials: SessionCredentials, pageContext: ConnectPageContext,
        response: ConnectResponse, customerIdentity: CrmSdkCustomerIdentity?
    ) {
        pauseEventCollection()
        let dropped = stateLock.withLock { () -> [TrackerEvent] in
            let changedUser = connectedUserToken != nil && connectedUserToken != credentials.userToken
            connectedUserToken = credentials.userToken
            guard changedUser else { return [] }
            let events = startupEvents
            startupEvents.removeAll()
            canBufferStartupEvents = false
            currentPageContext = nil
            return events
        }
        if !dropped.isEmpty {
            publish(.dropped(dropped.map(\.id), TrackerLocalization.trackingConsentUnavailable.localized))
        }
        trackerStateStore.setSystemCustomerID(customerIdentity?.customerId)
        trackerStateStore.setSiteCustomerID(customerIdentity?.siteCustomerId)
        trackerStateStore.setAvailability(
            response.behaviour?.tracker == true,
            requiresConsent: response.behaviour?.consentForm == true
        )
        trackerTimeSyncStore.setServerTimestamp(response.timestamp)
        stateLock.withLock {
            if canBufferStartupEvents, currentPageContext != nil { return }
            currentPageContext = pageContext.url.flatMap { url in
                guard url.scheme != nil else { return nil }
                return TrackerPageContext(
                    pageURL: url.absoluteString,
                    pageTitle: pageContext.title,
                    referrerURL: pageContext.referURL?.scheme == nil
                        ? nil : pageContext.referURL?.absoluteString
                )
            }
        }
        _ = enqueueInitialization(userToken: credentials.userToken)
    }

    package func sessionDidDisconnect() {
        eventRecordingQueue.sync { handleSessionDisconnect() }
    }

    private func handleSessionDisconnect() {
        pauseEventCollection()
        let resetError = stateLock.withLock { () -> TrackerError? in
            needsStorageReset = true
            do {
                if let storage {
                    try storage.clearForIdentityChange()
                    needsStorageReset = false
                }
                return nil
            } catch {
                let failure = TrackerError.storage(error.localizedDescription)
                storageInitializationError = failure
                return failure
            }
        }
        if let resetError { publish(.retryScheduled([], resetError)) }
        let dropped = stateLock.withLock { () -> [TrackerEvent] in
            let events = eventQueue.snapshot() + startupEvents
            eventQueue.clear()
            startupEvents.removeAll()
            canBufferStartupEvents = false
            currentPageContext = nil
            return events
        }
        if !dropped.isEmpty {
            publish(.dropped(dropped.map(\.id), TrackerLocalization.trackingConsentUnavailable.localized))
        }
        stateLock.withLock {
            initializationGeneration &+= 1
        }
        trackerStateStore.setSystemCustomerID(nil)
        trackerStateStore.setSiteCustomerID(nil)
        trackerStateStore.setAvailability(false, requiresConsent: false)
        trackerTimeSyncStore.clear()
        if let resetError { publishReadiness(error: resetError) }
        enqueueOperation { tracker in
            tracker.performDisconnect()
        }
    }
}
