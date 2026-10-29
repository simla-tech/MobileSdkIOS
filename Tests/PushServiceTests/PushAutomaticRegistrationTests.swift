import FirebaseCore
import Foundation
import XCTest
import UserNotifications
@testable import Core
@testable import PushService

@MainActor
final class PushAutomaticRegistrationTests: XCTestCase {
    private var databaseURL: URL!
    private var originalFirebaseOptions: FirebaseOptions?
    private var configuredFirebase = false

    override func setUp() async throws {
        // UNUserNotificationCenter requires an application-hosted test process.
        try XCTSkipUnless(Bundle.main.bundleURL.pathExtension == "app", "Requires an iOS application test host")
        originalFirebaseOptions = FirebaseApp.app()?.options
        await configureFirebase(project: "test-firebase")
        configuredFirebase = true
        databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PushAutomaticTests-\(UUID().uuidString).sqlite")
        PushRegistrationURLProtocol.reset()
    }

    override func tearDown() async throws {
        if let databaseURL { try? FileManager.default.removeItem(at: databaseURL) }
        if configuredFirebase {
            await deleteFirebaseApp()
            if let originalFirebaseOptions { FirebaseApp.configure(options: originalFirebaseOptions) }
        }
    }

    private func deleteFirebaseApp() async {
        guard let app = FirebaseApp.app() else { return }
        await withCheckedContinuation { continuation in
            app.delete { _ in continuation.resume() }
        }
    }

    private func configureFirebase(project: String) async {
        await deleteFirebaseApp()
        let options = FirebaseOptions(googleAppID: "1:123456789:ios:0123456789abcdef", gcmSenderID: "123456789")
        options.apiKey = "A" + String(repeating: "0", count: 38)
        options.projectID = project
        FirebaseApp.configure(options: options)
    }

    private func service(customer: Int64 = 1) -> PushService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushRegistrationURLProtocol.self]
        return PushService(
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "test-site"),
                customerIdentity: .init(customerId: customer, siteCustomerId: nil, siteCode: nil)),
            tokenRegistrator: .init(session: URLSession(configuration: configuration)),
            pushHandler: PushHandler(siteToken: "test-site", retryQueue: isolatedRetryQueue()),
            registrationStorage: .init(databaseURL: databaseURL)
        )
    }

    private func connect(_ service: PushService) throws {
        let response = try JSONDecoder().decode(ConnectResponse.self, from: Data(
            #"{"user":{"token":"user"},"session":{"id":1}}"#.utf8
        ))
        service.sessionDidConnect(credentials: .init(userToken: "user", sessionID: "1"),
            pageContext: .init(), user: .init(), response: response, customerIdentity: nil)
    }

    private func settle() async {
        // Allow lifecycle tasks, URLProtocol delivery and main-actor callbacks to settle.
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testStorageFailureIsReportedWithoutStartingRegistration() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        databaseURL = blocker.appendingPathComponent("registration.sqlite")
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        do {
            _ = try await service.registerNotificationCategories(["orders"])
            XCTFail("Expected a storage failure")
        } catch PushServiceError.storage(let message) {
            XCTAssertFalse(message.isEmpty)
        }
        XCTAssertEqual(PushRegistrationURLProtocol.count, 0)
    }

    func testRegistrationWaitsForTokenAndSession() async throws {
        let service = service()
        let applied = expectation(description: "Registration after readiness")
        service.registerNotificationCategories(["orders"]) { result in
            XCTAssertEqual(try? result.get(), .fcm("A"))
            applied.fulfill()
        }
        await settle()
        XCTAssertEqual(PushRegistrationURLProtocol.count, 0)
        service.setToken(.fcm("A"))
        await settle()
        XCTAssertEqual(PushRegistrationURLProtocol.count, 0)
        try connect(service)
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, ["orders"])
    }

    func testNoRequestUntilIntegratorSuppliesListIncludingEmpty() async throws {
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        await settle()
        XCTAssertEqual(PushRegistrationURLProtocol.count, 0)
        let token = try await service.registerNotificationCategories([])
        XCTAssertEqual(token, .fcm("A"))
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, [])
    }

    func testFullListsReplaceCategoriesAndEmptyUnsubscribes() async throws {
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        _ = try await service.registerNotificationCategories(["orders", "news"])
        _ = try await service.registerNotificationCategories(["news"])
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, ["news"])
        _ = try await service.registerNotificationCategories([])
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, [])
        _ = try await service.registerNotificationCategories([])
        XCTAssertEqual(PushRegistrationURLProtocol.count, 3)
    }

    func testCategoryOrderAndDuplicatesDoNotCauseRequests() async throws {
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        _ = try await service.registerNotificationCategories(["orders", "news"])
        _ = try await service.registerNotificationCategories(["news", "orders", "news"])
        XCTAssertEqual(PushRegistrationURLProtocol.count, 1)
    }

    func testRestartSkipsConfirmedRegistrationAndUnsubscription() async throws {
        for categories in [["orders"], []] {
            let first = service()
            first.setToken(.fcm("A"))
            try connect(first)
            _ = try await first.registerNotificationCategories(categories)
            let beforeRestart = PushRegistrationURLProtocol.count
            let restarted = service()
            restarted.setToken(.fcm("A"))
            try connect(restarted)
            _ = try await restarted.registerNotificationCategories(categories)
            XCTAssertEqual(PushRegistrationURLProtocol.count, beforeRestart)
        }
    }

    func testRestartRemovesOldSystemCategoriesAndPreservesUnrelatedCategories() async throws {
        let oldID = "old-\(UUID().uuidString)"
        let retainedID = "retained-\(UUID().uuidString)"
        let newID = "new-\(UUID().uuidString)"
        let unrelatedID = "unrelated-\(UUID().uuidString)"
        await addSystemCategory(unrelatedID)
        let first = service()
        first.setToken(.fcm("A"))
        try connect(first)
        _ = try await first.registerNotificationCategories([oldID, retainedID])
        await waitForSystemCategories { $0.contains(oldID) && $0.contains(retainedID) && $0.contains(unrelatedID) }

        let restarted = service()
        restarted.setToken(.fcm("A"))
        try connect(restarted)
        _ = try await restarted.registerNotificationCategories([retainedID, newID])
        await waitForSystemCategories {
            !$0.contains(oldID) && $0.contains(retainedID) && $0.contains(newID) && $0.contains(unrelatedID)
        }
        XCTAssertEqual(PushRegistrationURLProtocol.count, 2)
        _ = try await restarted.registerNotificationCategories([])
        await waitForSystemCategories {
            !$0.contains(oldID) && !$0.contains(retainedID) && !$0.contains(newID) && $0.contains(unrelatedID)
        }
        await removeSystemCategory(unrelatedID)
    }

    func testFailedListIsRetriedAfterRestart() async throws {
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        _ = try await service.registerNotificationCategories(["orders"])
        PushRegistrationURLProtocol.statusCode = 500
        do {
            _ = try await service.registerNotificationCategories(["news"])
            XCTFail("Expected server failure")
        } catch { }
        PushRegistrationURLProtocol.statusCode = 204
        let restarted = self.service()
        restarted.setToken(.fcm("A"))
        try connect(restarted)
        _ = try await restarted.registerNotificationCategories(["news"])
        _ = try await restarted.registerNotificationCategories(["news"])
        XCTAssertEqual(PushRegistrationURLProtocol.count, 3)
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, ["news"])
    }

    func testRestartRemovesUnconfirmedSystemCategories() async throws {
        let oldID = "confirmed-\(UUID().uuidString)"
        let failedID = "failed-\(UUID().uuidString)"
        let newID = "new-\(UUID().uuidString)"
        let first = service()
        first.setToken(.fcm("A"))
        try connect(first)
        _ = try await first.registerNotificationCategories([oldID])
        PushRegistrationURLProtocol.statusCode = 500
        do {
            _ = try await first.registerNotificationCategories([failedID])
            XCTFail("Expected server failure")
        } catch { }
        await waitForSystemCategories { !$0.contains(oldID) && $0.contains(failedID) }
        PushRegistrationURLProtocol.statusCode = 204
        let restarted = service()
        restarted.setToken(.fcm("A"))
        try connect(restarted)
        _ = try await restarted.registerNotificationCategories([newID])
        await waitForSystemCategories { !$0.contains(oldID) && !$0.contains(failedID) && $0.contains(newID) }
        _ = try await restarted.registerNotificationCategories([])
    }

    func testNewListSupersedesPendingCallBeforeReadiness() async throws {
        let service = service()
        let superseded = expectation(description: "Old list superseded")
        service.registerNotificationCategories(["orders"]) { result in
            guard case let .failure(error) = result else {
                XCTFail("Expected superseded result")
                superseded.fulfill()
                return
            }
            XCTAssertEqual(error, .operationSuperseded)
            superseded.fulfill()
        }
        let latest = expectation(description: "Latest list applied")
        service.registerNotificationCategories(["news"]) { result in
            XCTAssertEqual(try? result.get(), .fcm("A"))
            latest.fulfill()
        }
        service.setToken(.fcm("A"))
        try connect(service)
        await fulfillment(of: [superseded, latest], timeout: 2)
        XCTAssertEqual(PushRegistrationURLProtocol.count, 1)
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, ["news"])
    }

    func testListChangedDuringRequestIsAppliedAfterCurrentRequest() async throws {
        let service = service()
        let started = expectation(description: "First request started")
        PushRegistrationURLProtocol.responseDelay = 0.1
        PushRegistrationURLProtocol.onRequest = { started.fulfill() }
        let firstCompleted = expectation(description: "First request completed")
        service.registerNotificationCategories(["orders"]) { result in
            XCTAssertNotNil(try? result.get())
            firstCompleted.fulfill()
        }
        service.setToken(.fcm("A"))
        try connect(service)
        await fulfillment(of: [started], timeout: 2)
        PushRegistrationURLProtocol.onRequest = nil
        let lastCompleted = expectation(description: "Changed list completed")
        service.registerNotificationCategories(["news"]) { result in
            XCTAssertNotNil(try? result.get())
            lastCompleted.fulfill()
        }
        await fulfillment(of: [firstCompleted, lastCompleted], timeout: 2)
        XCTAssertEqual(PushRegistrationURLProtocol.count, 2)
        XCTAssertEqual(PushRegistrationURLProtocol.lastCategories, ["news"])
    }

    func testCustomerProjectAndTokenTypeChangesCauseRequests() async throws {
        let configurations: [(Int64, String, PushToken)] = [
            (1, "firebase", .fcm("A")), (2, "firebase", .fcm("A")),
            (2, "other", .fcm("A")), (2, "other", .fid("A"))
        ]
        for (customer, project, token) in configurations {
            await configureFirebase(project: project)
            let service = service(customer: customer)
            service.setToken(token)
            try connect(service)
            _ = try await service.registerNotificationCategories(["orders"])
        }
        XCTAssertEqual(PushRegistrationURLProtocol.count, configurations.count)
    }

    func testGlobalCallbackReportsRotatedTokenButNotCachedList() async throws {
        let service = service()
        service.setToken(.fcm("A"))
        try connect(service)
        _ = try await service.registerNotificationCategories(["orders"])
        let updated = expectation(description: "Updated token reported")
        service.onPushRegistrationResult = { result in
            XCTAssertEqual(try? result.get(), .fcm("B"))
            updated.fulfill()
        }
        service.setToken(.fcm("B"))
        await fulfillment(of: [updated], timeout: 2)
        let cached = expectation(description: "Cached list emits no event")
        cached.isInverted = true
        service.onPushRegistrationResult = { _ in cached.fulfill() }
        _ = try await service.registerNotificationCategories(["orders"])
        await fulfillment(of: [cached], timeout: 0.1)
        XCTAssertEqual(PushRegistrationURLProtocol.count, 2)
    }

    private func addSystemCategory(_ identifier: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().getNotificationCategories { categories in
                var updated = categories
                updated.insert(UNNotificationCategory(identifier: identifier, actions: [], intentIdentifiers: [], options: []))
                UNUserNotificationCenter.current().setNotificationCategories(updated)
                continuation.resume()
            }
        }
        await waitForSystemCategories { $0.contains(identifier) }
    }

    private func removeSystemCategory(_ identifier: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().getNotificationCategories { categories in
                UNUserNotificationCenter.current().setNotificationCategories(categories.filter { $0.identifier != identifier })
                continuation.resume()
            }
        }
    }

    private func waitForSystemCategories(_ predicate: (Set<String>) -> Bool) async {
        for _ in 0..<100 {
            let identifiers: Set<String> = await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().getNotificationCategories { categories in
                    continuation.resume(returning: Set(categories.map(\.identifier)))
                }
            }
            if predicate(identifiers) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for system categories")
    }
}

final class PushRegistrationURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bodies: [[String: Any]] = []
    static var count: Int { lock.withLock { bodies.count } }
    static var lastCategories: [String]? { lock.withLock { bodies.last?["categories"] as? [String] } }
    private static var responseStatus = 204
    static var statusCode: Int {
        get { lock.withLock { responseStatus } }
        set { lock.withLock { responseStatus = newValue } }
    }
    private static var delay: TimeInterval = 0
    private static var requestObserver: (() -> Void)?
    static var responseDelay: TimeInterval {
        get { lock.withLock { delay } }
        set { lock.withLock { delay = newValue } }
    }
    static var onRequest: (() -> Void)? {
        get { lock.withLock { requestObserver } }
        set { lock.withLock { requestObserver = newValue } }
    }
    static func reset() { lock.withLock { bodies = []; responseStatus = 204; delay = 0; requestObserver = nil } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let (status, delay, observer) = Self.lock.withLock { () -> (Int, TimeInterval, (() -> Void)?) in
            Self.bodies.append(body)
            return (Self.responseStatus, Self.delay, Self.requestObserver)
        }
        observer?()
        let respond = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
        } else {
            respond()
        }
    }
    override func stopLoading() {}
}
