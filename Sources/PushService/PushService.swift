import CryptoKit
import FirebaseCore
import UIKit
import PushNotificationExtension
import FirebaseInstallations
import FirebaseMessaging
import Foundation
import Core
import UserNotifications

/// Entry point for apps that manage Firebase/APNs integration themselves.
///
/// Use `PushService` to register FCM tokens or Firebase installation IDs and to report notification
/// status changes when the host app already owns notification delegates and Firebase setup.
public final class PushService: NSObject {

    /// Called on the main queue when a RetailCRM notification or button is opened.
    /// Receives the action string and optional `ca_` attributes, including when no URL exists.
    /// The application decides how to navigate; dismissing a notification does not call this handler.
    @MainActor public var onNotificationOpen: ((NotificationAction) -> Void)?

    /// Reports each completed backend registration or unregistration attempt on the main actor.
    /// Reusing a confirmed registration does not emit a result.
    @MainActor public var onPushRegistrationResult: ((Result<PushToken, PushServiceError>) -> Void)?

    /// Receives the current retry queue and future push-status retry updates for this site.
    /// Callbacks run off the main thread. Assign nil to unsubscribe; extension updates stay in its process.
    public var onStatusRetryUpdate: ((PushStatusRetryUpdate) -> Void)? {
        get { pushHandler.onStatusRetryUpdate }
        set { pushHandler.onStatusRetryUpdate = newValue }
    }

    @MainActor private static var systemCategoriesTask: Task<Void, Error>?
    @MainActor private var categories: [String]?
    @MainActor private var registrationTask: Task<Void, Never>?
    @MainActor private var registrationNeedsUpdate = false
    @MainActor private var pendingRegistrationCompletions: [(Result<PushToken, PushServiceError>) -> Void] = []
    private let registrationStorageKey: String
    private let sessionRuntime: SessionRuntime
    private let tokenRegistrator: PushTokenRegistrator
    private let pushHandler: PushHandler
    private let registrationStorage: PushRegistrationStorage

    @MainActor private var pushToken: PushToken?
    @MainActor private var sessionReadyForPushRegistration = false {
        didSet {
            scheduleAutomaticRegistration()
        }
    }

    /// Creates a push service connected to the shared SDK session.
    package init(
        sessionRuntime: SessionRuntime,
        tokenRegistrator: PushTokenRegistrator? = nil,
        pushHandler: PushHandler,
        registrationStorage: PushRegistrationStorage = .init()
    ) {
        self.sessionRuntime = sessionRuntime
        self.tokenRegistrator = tokenRegistrator ?? .init(
            clientAPIEndpointURL: sessionRuntime.config.endpoints.clientAPIEndpointURL
        )
        self.registrationStorage = registrationStorage
        let siteHash = SHA256.hash(data: Data(sessionRuntime.config.siteToken.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.registrationStorageKey = siteHash
        self.pushHandler = pushHandler
        super.init()
    }

    /// Replaces the complete desired subscription. An empty list unsubscribes from all categories.
    /// Waits for a valid token and connected customer session; skips an already confirmed request.
    @MainActor
    public func registerNotificationCategories(_ categories: [String]) async throws -> PushToken {
        try await withCheckedThrowingContinuation { continuation in
            registerNotificationCategories(categories, completion: { continuation.resume(with: $0) })
        }
    }

    /// Sets an FCM token or Firebase installation ID obtained by the application.
    ///
    /// - Parameters:
    ///   - token: FCM token or Firebase Installation ID obtained by the application.
    @MainActor
    public func setToken(_ token: PushToken) {
        self.pushToken = token
        self.scheduleAutomaticRegistration()
    }

    /// Resolves an APNs device token to an FCM token or Firebase installation ID.
    @MainActor
    public func setDeviceToken(_ token: Data) async throws -> PushToken {
        try await withCheckedThrowingContinuation { continuation in
            setDeviceToken(token, completion: { continuation.resume(with: $0) })
        }
    }
}

/// Completion-based push service API.
public extension PushService {

    /// Replaces the full category list, updates iOS categories and applies the backend subscription.
    /// Completion runs on the main actor after backend acceptance, cached confirmation or failure.
    /// A different list replaces pending calls with operationSuperseded before their request starts.
    @MainActor
    func registerNotificationCategories(
        _ categories: [String],
        completion: @escaping (Result<PushToken, PushServiceError>) -> Void
    ) {
        let desired = Array(Set(categories)).sorted()
        let superseded = self.categories != nil && self.categories != desired ? pendingRegistrationCompletions : []
        let previousDesired: [String]
        do {
            previousDesired = try registrationStorage.setDesiredCategories(desired, site: registrationStorageKey)
        } catch {
            completion(.failure(.storage(error.localizedDescription)))
            return
        }
        if self.categories != desired { pendingRegistrationCompletions.removeAll() }
        self.categories = desired
        let systemUpdate = Self.updateSystemNotificationCategories(
            desired, storage: registrationStorage, site: registrationStorageKey, previousDesired: previousDesired
        )
        let finish: (Result<PushToken, PushServiceError>) -> Void = { result in
            Task { @MainActor in
                do {
                    try await systemUpdate.value
                    completion(result)
                } catch {
                    completion(.failure(.storage(error.localizedDescription)))
                }
            }
        }
        pendingRegistrationCompletions.append(finish)
        scheduleAutomaticRegistration()
        superseded.forEach { $0(.failure(.operationSuperseded)) }
    }

    /// Passes an APNs device token to Firebase and obtains an FCM token or Firebase installation ID.
    ///
    /// - Parameters:
    ///   - token: APNs device token used to obtain a Firebase push identifier.
    ///   - completion: Receives the FCM token or Firebase installation ID, or an error.
    @MainActor
    func setDeviceToken(
        _ token: Data,
        completion: @escaping (Result<PushToken, PushServiceError>) -> Void
    ) {
        pushToken = nil
        scheduleAutomaticRegistration()
        getToken(deviceToken: token) { [weak self] result in
            switch result {
            case .success(let token):
                self?.pushToken = token
                self?.scheduleAutomaticRegistration()
                completion(.success((token)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Reports `.delivered` for a RetailCRM silent notification received by the app delegate.
    /// Returns `true` and calls the completion handler with `.noData` after reporting the status.
    /// Returns `false` without calling the handler for other notifications.
    /// Calls `completion` with the status reporting result only for handled notifications.
    ///
    /// - Parameters:
    ///   - userInfo: Payload of the remote notification.
    ///   - completionHandler: System callback invoked after handling a RetailCRM notification.
    ///   - completion: Receives the status reporting result for a handled RetailCRM notification.
    func handleSilentNotification(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
        completion: @escaping (Result<Void, PushServiceError>) -> Void = { _ in }
    ) -> Bool {
        self.pushHandler.handleSilentNotification(
            userInfo,
            completion: { result in
                completionHandler(.noData)
                completion(Self.statusReportingResult(result))
            }
        )
    }

    /// Reports `.delivered` for a RetailCRM foreground notification.
    /// Returns `true` and calls the completion handler with banner, badge, and sound options.
    /// Returns `false` without calling the handler for other notifications.
    /// Calls `completion` with the status reporting result only for handled notifications.
    ///
    /// - Parameters:
    ///   - notification: Notification delivered while the application is in the foreground.
    ///   - completionHandler: System callback invoked after handling a RetailCRM notification.
    ///   - completion: Receives the status reporting result for a handled RetailCRM notification.
    @discardableResult
    func handleWillPresent(
        _ notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
        completion: @escaping (Result<Void, PushServiceError>) -> Void = { _ in }
    ) -> Bool {
        self.pushHandler.handleWillPresent(
            notification,
            completion: { result in
                completionHandler([.banner, .badge, .sound])
                completion(Self.statusReportingResult(result))
            }
        )
    }

    /// Reports `.clicked` or `.swiped` for a RetailCRM notification response.
    /// Calls `onNotificationOpen` for opens and button taps, then completes the handled response.
    /// Returns `false` without calling the completion handler for other notifications.
    /// Calls `completion` with the status reporting result only for handled notifications.
    ///
    /// - Parameters:
    ///   - response: User response to a delivered notification.
    ///   - completionHandler: System callback invoked after handling a RetailCRM notification.
    ///   - completion: Receives the status reporting result for a handled RetailCRM notification.
    @discardableResult
    func handleDidReceive(
        _ response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
        completion: @escaping (Result<Void, PushServiceError>) -> Void = { _ in }
    ) -> Bool {
        let group = DispatchGroup()
        group.enter()
        switch pushHandler.handleDidReceive(
            response,
            completion: { result in
                group.leave()
                completion(Self.statusReportingResult(result))
            }
        ) {
        case .handled(let push):
            if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                let userInfo = response.notification.request.content.userInfo
                if let utm = CrmUtmAttribution(
                    source: userInfo["utm_source"] as? String,
                    medium: userInfo["utm_medium"] as? String,
                    campaign: userInfo["utm_campaign"] as? String,
                    term: userInfo["utm_term"] as? String,
                    content: userInfo["utm_content"] as? String
                ) {
                    CrmUtmAttributionStorage.shared.save(utm)
                }
                let action = NotificationAction(
                    urlString: pushHandler.actionURLString(in: push, for: response.actionIdentifier),
                    customAttributes: push.clickAction?.customAttributes
                )
                group.enter()
                DispatchQueue.main.async {
                    self.onNotificationOpen?(action)
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completionHandler()
            }
            return true
        case .notHandled:
            group.leave()
            return false
        }
    }
}

private extension PushService {

    @MainActor
    static func updateSystemNotificationCategories(
        _ desired: [String], storage: PushRegistrationStorage, site: String, previousDesired: [String]
    ) -> Task<Void, Error> {
        let previous = systemCategoriesTask
        let task = Task { @MainActor in
            _ = try? await previous?.value
            let state = try storage.load(site: site)
            let managed = state.systemCategories ?? previousDesired
            let confirmed = state.confirmedCategories ?? []
            let desiredIDs = Set(desired)
            let ownedIDs = Set(managed).union(confirmed).union(desiredIDs)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                UNUserNotificationCenter.current().getNotificationCategories { registered in
                    var updated = registered.filter { !ownedIDs.contains($0.identifier) }
                    for identifier in desiredIDs {
                        updated.insert(UNNotificationCategory(
                            identifier: identifier, actions: [], intentIdentifiers: [], options: [.customDismissAction]
                        ))
                    }
                    UNUserNotificationCenter.current().setNotificationCategories(updated)
                    continuation.resume()
                }
            }
            try storage.setSystemCategories(desired, site: site)
        }
        systemCategoriesTask = task
        return task
    }

    static func statusReportingResult(
        _ result: Result<Void, PushStatusReportingError>
    ) -> Result<Void, PushServiceError> {
        result.mapError { error in
            let failure: PushServiceError.StatusReportingFailure
            switch error {
            case let .requestEncodingFailed(message):
                failure = .requestEncodingFailed(message)
            case let .invalidHTTPResponse(description):
                failure = .invalidHTTPResponse(description)
            case let .requestFailed(message):
                failure = .requestFailed(message)
            case let .httpStatus(statusCode, messages):
                failure = .httpStatus(statusCode, messages)
            }
            return .statusReporting(failure)
        }
    }

    @MainActor
    func scheduleAutomaticRegistration() {
        registrationNeedsUpdate = true
        guard registrationTask == nil else { return }
        registrationTask = Task { @MainActor in
            defer { registrationTask = nil }
            while registrationNeedsUpdate {
                registrationNeedsUpdate = false
                let identity = await sessionRuntime.customerIdentity
                // No list means the integrator has not configured this launch yet; [] means unsubscribe.
                guard sessionReadyForPushRegistration,
                      let pushToken, (try? pushToken.normalizedToken()) != nil,
                      let identity, let savedCategories = categories else { return }
                let completions = pendingRegistrationCompletions
                pendingRegistrationCompletions.removeAll()
                var result: Result<PushToken, PushServiceError>
                do {
                    let validatedIdentity: CrmSdkCustomerIdentity
                    do {
                        validatedIdentity = try identity.validated()
                    } catch {
                        throw PushServiceError.invalidCustomerIdentity(error.localizedDescription)
                    }
                    let token = try pushToken.normalizedToken()
                    let projectID = try resolvedFirebaseProjectId()
                    let categories = Array(Set(savedCategories)).sorted()
                    let body = PushTokenRequestBody(
                        customerId: validatedIdentity.customerId,
                        customerExternalId: validatedIdentity.siteCustomerId,
                        crmSiteCode: validatedIdentity.siteCode,
                        token: token.fcmValue, fid: token.fidValue,
                        firebaseProjectId: projectID, categories: categories
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    var registrationData: Data
                    do {
                        registrationData = try encoder.encode(body)
                    } catch {
                        throw PushServiceError.requestEncodingFailed(error.localizedDescription)
                    }
                    registrationData.append(Data(sessionRuntime.config.endpoints.clientAPIEndpointURL.absoluteString.utf8))
                    let fingerprint = SHA256.hash(data: registrationData)
                        .map { String(format: "%02x", $0) }.joined()
                    if try registrationStorage.load(site: registrationStorageKey).fingerprint == fingerprint {
                        completions.forEach { $0(.success(token)) }
                        continue
                    }
                    // A failed/interrupted request may have reached the backend; invalidate the old state.
                    try registrationStorage.invalidateFingerprint(site: registrationStorageKey)
                    result = await withCheckedContinuation { continuation in
                        tokenRegistrator.registerToken(
                            token, customerIdentity: validatedIdentity, siteToken: sessionRuntime.config.siteToken,
                            firebaseProjectId: projectID, categories: categories
                        ) { continuation.resume(returning: $0) }
                    }
                    if case .success = result {
                        try registrationStorage.confirm(fingerprint: fingerprint, categories: categories, site: registrationStorageKey)
                    }
                } catch {
                    if let error = error as? PushServiceError {
                        result = .failure(error)
                    } else {
                        result = .failure(.storage(error.localizedDescription))
                    }
                }
                onPushRegistrationResult?(result)
                completions.forEach { $0(result) }
            }
        }
    }

    @MainActor
    func getToken(deviceToken: Data, completion: @escaping (Result<PushToken, PushServiceError>) -> Void) {
        Messaging.messaging().apnsToken = deviceToken

        if Messaging.messaging().isInstallationIdEnabled {
            messagingRegisterIfPossible { [weak self] result in
                switch result {
                case .success:
                    self?.getFidToken { result in
                        completion(result.map(PushToken.fid))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            getFcmToken { result in
                completion(result.map(PushToken.fcm))
            }
        }
    }

    func messagingRegisterIfPossible(completion: @escaping (Result<Void, PushServiceError>) -> Void) {
        guard Messaging.messaging().isInstallationIdEnabled else {
            completion(.failure(.firebaseInstallationIDDisabled))
            return
        }

        Messaging.messaging().register { error in
            if let error {
                completion(.failure(.firebaseMessaging(error)))
                return
            }
            completion(.success(()))
        }
    }

    func getFcmToken(completion: @escaping (Result<String, PushServiceError>) -> Void) {
        Messaging.messaging().token { token, error in
            if let error {
                completion(.failure(.firebaseMessaging(error)))
                return
            }
            guard let token else {
                completion(.failure(.emptyFCMToken))
                return
            }
            completion(.success(token))
        }
    }

    func getFidToken(completion: @escaping (Result<String, PushServiceError>) -> Void) {
        Installations.installations().installationID { token, error in
            if let error {
                completion(.failure(.firebaseInstallations(error)))
                return
            }
            guard let token else {
                completion(.failure(.emptyFID))
                return
            }
            completion(.success(token))
        }
    }

    func resolvedFirebaseProjectId() throws -> String {
        if let firebaseProjectId = FirebaseApp.app()?.options.projectID?.nilIfEmpty {
            return firebaseProjectId
        }
        throw PushServiceError.emptyFirebaseProjectID
    }
}

extension PushService: SessionLifecycleListener {
    package func sessionDidConnect(
        credentials: SessionCredentials,
        pageContext: ConnectPageContext,
        user: ConnectUser,
        response _: ConnectResponse,
        customerIdentity _: CrmSdkCustomerIdentity?
    ) {
        Task { @MainActor [weak self] in
            guard let _ = await self?.sessionRuntime.customerIdentity else {
                self?.sessionReadyForPushRegistration = false
                return
            }
            self?.sessionReadyForPushRegistration = true
        }
    }

    package func sessionDidDisconnect() {
        Task { @MainActor [weak self] in
            self?.sessionReadyForPushRegistration = false
        }
    }
}
