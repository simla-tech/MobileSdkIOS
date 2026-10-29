import Foundation
import SQLite3
import XCTest
@testable import Core
@testable import Tracker

final class TrackerReadinessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReadinessProtocol.configure()
    }

    func testPreparationWaitsForSharedConnectionWithoutConnectingItself() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let waiting = expectation(description: "No readiness before connection")
        waiting.isInverted = true
        fixture.tracker.onReadyUpdate = { _, _ in waiting.fulfill() }
        await fulfillment(of: [waiting], timeout: 0.05)
        XCTAssertEqual(ReadinessProtocol.requestCount, 0)
        XCTAssertFalse(fixture.storage.hasActiveScope)

        let ready = expectation(description: "Prepared automatically after connection")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(needsForm)
            XCTAssertNil(error)
            XCTAssertTrue(fixture.storage.hasActiveScope)
            ready.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(ReadinessProtocol.requestCount, 1)
    }

    func testTrackerCreatedAfterConnectionPreparesAndReplaysForLateSubscriber() async throws {
        let fixture = try await makeFixture(createAfterConnection: true)
        defer { fixture.cleanUp() }
        let first = expectation(description: "First subscriber")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(needsForm)
            XCTAssertNil(error)
            first.fulfill()
        }
        await fulfillment(of: [first], timeout: 2)
        fixture.tracker.onReadyUpdate = nil
        let late = expectation(description: "Late subscriber gets cached result")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(needsForm)
            XCTAssertNil(error)
            late.fulfill()
        }
        await fulfillment(of: [late], timeout: 2)
        XCTAssertEqual(ReadinessProtocol.requestCount, 1)
    }

    func testConsentChangeUpdatesCachedReadinessFlag() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let unknown = expectation(description: "Consent form required")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(needsForm)
            XCTAssertNil(error)
            unknown.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [unknown], timeout: 2)
        fixture.tracker.onReadyUpdate = nil
        try fixture.tracker.setConsent(.granted).get()
        let restored = expectation(description: "Late subscriber sees granted consent")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertFalse(needsForm)
            XCTAssertNil(error)
            restored.fulfill()
        }
        await fulfillment(of: [restored], timeout: 2)
        fixture.tracker.onReadyUpdate = nil
        let requiredAgain = expectation(description: "Readiness updates after consent changes")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertNil(error)
            if needsForm { requiredAgain.fulfill() }
        }
        try fixture.tracker.setConsent(.unknown).get()
        await fulfillment(of: [requiredAgain], timeout: 2)
    }

    func testSavedConsentIsAppliedBeforeAutomaticPreparation() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        try fixture.tracker.setConsent(.denied).get()
        let ready = expectation(description: "Saved decision suppresses consent form")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertFalse(needsForm)
            XCTAssertNil(error)
            ready.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertTrue(fixture.tracker.requiresConsent)
    }

    func testConnectionFailureIsReportedAndLaterConnectionRecovers() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        ReadinessProtocol.configure(status: 503)
        let failed = expectation(description: "Shared connection failure")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(needsForm)
            XCTAssertEqual(error, .httpStatus(503, ["Unavailable"], retryAfter: nil))
            failed.fulfill()
        }
        do {
            _ = try await fixture.runtime.start()
            XCTFail("Expected connection failure")
        } catch {}
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(fixture.storage.hasActiveScope)
        let recovered = expectation(description: "Later successful connection")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            if error == nil {
                XCTAssertTrue(needsForm)
                recovered.fulfill()
            }
        }
        ReadinessProtocol.configure()
        _ = try await fixture.runtime.start()
        await fulfillment(of: [recovered], timeout: 2)
    }

    func testTrackerCreatedAfterConnectionFailureGetsCurrentErrorWithoutRetrying() async throws {
        ReadinessProtocol.configure(status: 503)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadinessProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site"), session: session, userTokenStorage: ReadinessTokenStorage()
        )
        _ = try? await runtime.start()
        let tracker = Tracker(config: TrackerConfig(flushInterval: 0), sessionRuntime: runtime)
        let failed = expectation(description: "Previously failed connection replayed")
        tracker.onReadyUpdate = { needsForm, error in
            XCTAssertFalse(needsForm)
            XCTAssertEqual(error, .httpStatus(503, ["Unavailable"], retryAfter: nil))
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(ReadinessProtocol.requestCount, 1)
    }

    func testStoragePreparationFailureReachesReadyHandler() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "DROP TABLE tracker_events;", nil, nil, nil), SQLITE_OK)
        let failed = expectation(description: "Local queue preparation failed")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(needsForm)
            guard case .storage? = error else { return XCTFail("Expected storage failure: \(String(describing: error))") }
            failed.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [failed], timeout: 2)
    }

    func testReconnectDoesNotReplayOldReadinessWhileNewSessionIsConnecting() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let ready = expectation(description: "First session ready")
        fixture.tracker.onReadyUpdate = { _, error in
            XCTAssertNil(error)
            ready.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [ready], timeout: 2)
        fixture.tracker.onReadyUpdate = nil
        ReadinessProtocol.configure(hold: true)
        let reconnect = Task {
            try await fixture.runtime.setCustomerIdentity(CrmSdkCustomerIdentity(customerId: 42))
        }
        await waitUntil { ReadinessProtocol.hasHeldResponse }
        let waiting = expectation(description: "Old session result is not replayed")
        waiting.isInverted = true
        fixture.tracker.onReadyUpdate = { _, _ in waiting.fulfill() }
        await fulfillment(of: [waiting], timeout: 0.05)
        let reconnected = expectation(description: "New session prepared")
        fixture.tracker.onReadyUpdate = { needsForm, error in
            XCTAssertTrue(needsForm)
            XCTAssertNil(error)
            reconnected.fulfill()
        }
        ReadinessProtocol.releaseResponse()
        try await reconnect.value
        await fulfillment(of: [reconnected], timeout: 2)
    }

    func testAutomaticLifecycleRegistrationDoesNotRetainTracker() async {
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "site"))
        var tracker: Tracker? = Tracker(config: TrackerConfig(flushInterval: 0), sessionRuntime: runtime)
        weak var released = tracker
        if let tracker { await runtime.addLifecycleListener(tracker) }
        tracker = nil
        await waitUntil { released == nil }
    }

    private func makeFixture(createAfterConnection: Bool = false) async throws -> Fixture {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadinessProtocol.self]
        let session = URLSession(configuration: configuration)
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site"), session: session, userTokenStorage: ReadinessTokenStorage()
        )
        if createAfterConnection { _ = try await runtime.start() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ready-\(UUID().uuidString).sqlite")
        let storage = try SQLiteTrackerStorage(databaseURL: url)
        let tracker = Tracker(config: TrackerConfig(flushInterval: 0), sessionRuntime: runtime, storage: storage)
        return Fixture(tracker: tracker, runtime: runtime, storage: storage, session: session, url: url)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private struct Fixture {
        let tracker: Tracker
        let runtime: SessionRuntime
        let storage: SQLiteTrackerStorage
        let session: URLSession
        let url: URL
        func cleanUp() {
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private final class ReadinessTokenStorage: UserTokenStorage {
    func getUserToken(siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws -> String? { nil }
    func setUserToken(_ token: String?, siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws {}
}

private final class ReadinessProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var status = 200
    private static var requests = 0
    private static var holdsResponse = false
    private static var heldResponse: ReadinessProtocol?
    static var requestCount: Int { lock.withLock { requests } }
    static var hasHeldResponse: Bool { lock.withLock { heldResponse != nil } }
    static func configure(status: Int = 200, hold: Bool = false) {
        lock.withLock { self.status = status; requests = 0; holdsResponse = hold }
    }
    static func releaseResponse() {
        let response = lock.withLock { () -> ReadinessProtocol? in
            defer { heldResponse = nil; holdsResponse = false }
            return heldResponse
        }
        response?.respond()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let held = Self.lock.withLock {
            Self.requests += 1
            if Self.holdsResponse { Self.heldResponse = self }
            return Self.holdsResponse
        }
        if !held { respond() }
    }
    private func respond() {
        let status = Self.lock.withLock { Self.status }
        let body = status == 200
            ? #"{"ts":"2026-10-28T12:00:00Z","user":{"token":"user"},"session":{"id":1},"behaviour":{"tracker":true,"consent_form":true}}"#
            : #"{"errors":["Unavailable"]}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
