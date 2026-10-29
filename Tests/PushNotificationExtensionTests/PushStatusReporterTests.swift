import Foundation
import XCTest
@testable import PushNotificationExtension

final class PushStatusReporterTests: XCTestCase {
    func testRetryPreservesEventAndCompletesInitialAttemptOnlyOnce() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        StatusRetryProtocol.reset([.http(503), .http(204)])
        let firstAttempt = expectation(description: "Initial failure returned without waiting for retries")
        firstAttempt.assertForOverFulfill = true
        fixture.reporter.reportStatus(.clicked, pushId: "push-id", buttonHash: "button-hash", siteToken: "site") {
            guard case .failure(let error) = $0 else { return XCTFail("Expected initial failure") }
            XCTAssertEqual(error, .httpStatus(503, []))
            firstAttempt.fulfill()
        }
        await fulfillment(of: [firstAttempt], timeout: 2)
        await waitUntil { StatusRetryProtocol.requests.count == 2 && fixture.isQueueEmpty }
        let requests = StatusRetryProtocol.requests
        let bodies = try requests.map { try JSONDecoder().decode(PushStatusRequestBody.self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.first, bodies.last)
        XCTAssertEqual(bodies.first?.buttonHash, "button-hash")
        XCTAssertEqual(bodies.first?.status, .clicked)
        XCTAssertEqual(bodies.first?.pushId, "push-id")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Site-Token") == "site" })
    }

    func testTransientFailuresAreRetried() async {
        for reply in [StatusRetryProtocol.Reply.offline, .nonHTTP, .http(408), .http(425), .http(429), .http(500), .http(599)] {
            let fixture = makeFixture()
            StatusRetryProtocol.reset([reply, .http(200)])
            let failed = expectation(description: "First attempt failed")
            fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site") { result in
                guard case .failure = result else { return XCTFail("Expected first failure") }
                failed.fulfill()
            }
            await fulfillment(of: [failed], timeout: 2)
            await waitUntil { StatusRetryProtocol.requests.count == 2 && fixture.isQueueEmpty }
            fixture.cleanUp()
        }
    }

    func testPermanentClientErrorsAreNotQueued() async {
        for status in [400, 401, 403, 404, 422] {
            let fixture = makeFixture()
            StatusRetryProtocol.reset([.http(status)])
            let failed = expectation(description: "Permanent failure")
            fixture.reporter.reportStatus(.swiped, pushId: "push", siteToken: "site") { result in
                guard case .failure(let error) = result else { return XCTFail("Expected permanent failure") }
                XCTAssertEqual(error, .httpStatus(status, []))
                failed.fulfill()
            }
            await fulfillment(of: [failed], timeout: 2)
            XCTAssertTrue(fixture.isQueueEmpty)
            XCTAssertEqual(StatusRetryProtocol.requests.count, 1)
            fixture.cleanUp()
        }
    }

    func testRetryAfterIsRespected() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        StatusRetryProtocol.reset([.http(429, retryAfter: "1"), .http(204)])
        let failed = expectation(description: "Rate limit returned")
        fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site") { _ in failed.fulfill() }
        await fulfillment(of: [failed], timeout: 2)
        let started = Date()
        await waitUntil { StatusRetryProtocol.requests.count == 2 && fixture.isQueueEmpty }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.9)
    }

    func testPendingFailureIsRestoredAfterReporterIsRecreated() async throws {
        let databaseURL = temporaryURL()
        let storage = PushStatusRetryStorage(databaseURL: databaseURL)
        let session = makeSession()
        defer {
            session.invalidateAndCancel()
        }
        StatusRetryProtocol.reset([.offline, .http(204)])
        var queue: PushStatusRetryQueue? = PushStatusRetryQueue(
            storage: storage, baseDelay: 1, monitorsNetwork: false
        )
        weak var previousQueue = queue
        let customURL = URL(string: "https://consultant.example.com/api/client/v1")!
        var reporter: PushStatusReporter? = .init(
            session: session, retryQueue: try XCTUnwrap(queue), clientAPIEndpointURL: customURL
        )
        let failed = expectation(description: "Failed event saved")
        reporter?.reportStatus(.clicked, pushId: "saved-push", buttonHash: "hash", siteToken: "saved-site") { _ in
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 2)
        let entries = try storage.loadPending()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.attempts, 1)
        reporter = nil
        queue = nil
        await waitUntil { previousQueue == nil }

        let restoredStorage = PushStatusRetryStorage(databaseURL: databaseURL)
        let restored = PushStatusRetryQueue(storage: restoredStorage, baseDelay: 0.01, monitorsNetwork: false)
        let newReporter = PushStatusReporter(session: session, retryQueue: restored)
        defer { withExtendedLifetime(newReporter) {} }
        await waitUntil { StatusRetryProtocol.requests.count == 2 }
        let request = try XCTUnwrap(StatusRetryProtocol.requests.last)
        XCTAssertEqual(request.url, customURL.appendingPathComponent("push-tokens/set-status"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Site-Token"), "saved-site")
        let body = try JSONDecoder().decode(PushStatusRequestBody.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.pushId, "saved-push")
        XCTAssertEqual(body.buttonHash, "hash")
        await waitUntil {
            (try? restoredStorage.loadPending().isEmpty) == true
        }
    }

    func testRestoredAttemptBudgetAllowsOnlyTheRemainingAttempt() async throws {
        let databaseURL = temporaryURL()
        let storage = PushStatusRetryStorage(databaseURL: databaseURL)
        try storage.save(.init(
            id: UUID(), body: .init(changedAt: 100, pushId: "push", status: .delivered, buttonHash: nil),
            siteToken: "site", clientAPIEndpointURL: URL(string: "https://c.retailcrm.tech/api/client/v1")!,
            attempts: 4, nextAttemptAt: Date()
        ))
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        StatusRetryProtocol.reset([.offline])
        let queue = PushStatusRetryQueue(storage: storage, baseDelay: 0.01, monitorsNetwork: false)
        let reporter = PushStatusReporter(session: session, retryQueue: queue)
        defer { withExtendedLifetime(reporter) {} }
        await waitUntil { StatusRetryProtocol.requests.count == 1 && (try? storage.loadPending().isEmpty) == true }
        let body = try JSONDecoder().decode(PushStatusRequestBody.self, from: XCTUnwrap(StatusRetryProtocol.requests.first?.httpBody))
        XCTAssertEqual(body.changedAt, 100)
    }

    func testRemovingOneStatusPreservesOtherStoredEntries() async throws {
        let session = makeSession()
        let databaseURL = temporaryURL()
        let storage = PushStatusRetryStorage(databaseURL: databaseURL)
        let queue = PushStatusRetryQueue(storage: storage, baseDelay: 3_600, monitorsNetwork: false)
        let reporter = PushStatusReporter(session: session, retryQueue: queue)
        defer {
            session.invalidateAndCancel()
        }
        StatusRetryProtocol.reset([.http(500)])
        let saved = expectation(description: "Both statuses saved")
        saved.expectedFulfillmentCount = 2
        reporter.reportStatus(.delivered, pushId: "first", siteToken: "site") { _ in saved.fulfill() }
        reporter.reportStatus(.clicked, pushId: "second", buttonHash: "hash", siteToken: "site") { _ in saved.fulfill() }
        await fulfillment(of: [saved], timeout: 2)
        StatusRetryProtocol.reset([.http(204)])
        let removed = expectation(description: "First status removed")
        reporter.reportStatus(.delivered, pushId: "first", siteToken: "site") { _ in removed.fulfill() }
        await fulfillment(of: [removed], timeout: 2)

        let entries = try storage.loadPending()
        XCTAssertEqual(entries.count, 1)
        let body = try XCTUnwrap(entries.first?.body)
        XCTAssertEqual(body.pushId, "second")
        XCTAssertEqual(body.buttonHash, "hash")
        XCTAssertEqual(entries.first?.attempts, 1)
    }

    func testObserverReportsRetryLifecycleWithStableEventIdentity() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let observation = PushStatusRetryObservation(siteToken: "site", queue: fixture.queue)
        let updates = RetryUpdatesRecorder()
        observation.onUpdate = { updates.append($0) }
        defer { withExtendedLifetime(observation) {} }
        StatusRetryProtocol.reset([.http(503), .http(429), .http(204)])
        fixture.reporter.reportStatus(.clicked, pushId: "push", buttonHash: "hash", siteToken: "site")
        await waitUntil { updates.values.count == 6 }
        let values = updates.values
        guard values.count == 6,
              case .queued(let event, .httpStatus(503, [])) = values[0],
              case .retryScheduled(let scheduled, 2, let firstDate, .httpStatus(503, [])) = values[1],
              case .sending(let sending, 2) = values[2],
              case .retryScheduled(let rescheduled, 3, let secondDate, .httpStatus(429, [])) = values[3],
              case .sending(let sendingAgain, 3) = values[4],
              case .delivered(let delivered) = values[5] else {
            return XCTFail("Unexpected retry lifecycle: \(values)")
        }
        XCTAssertEqual([scheduled, sending, rescheduled, sendingAgain, delivered], Array(repeating: event, count: 5))
        XCTAssertEqual(event.pushID, "push")
        XCTAssertEqual(event.status, .clicked)
        XCTAssertEqual(event.buttonHash, "hash")
        XCTAssertLessThan(firstDate, secondDate)
    }

    func testObserverReportsExhaustedAttempts() async {
        for reply in [StatusRetryProtocol.Reply.http(503), .offline] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            let observation = PushStatusRetryObservation(siteToken: "site", queue: fixture.queue)
            let updates = RetryUpdatesRecorder()
            observation.onUpdate = { updates.append($0) }
            defer { withExtendedLifetime(observation) {} }
            StatusRetryProtocol.reset([reply])
            let failed = expectation(description: "Initial attempt failed: \(reply)")
            fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site") { _ in failed.fulfill() }
            await fulfillment(of: [failed], timeout: 2)
            await waitUntil {
                if case .dropped(_, 5, _)? = updates.values.last { return true }
                return false
            }
            if case .http = reply {
                guard case .dropped(_, 5, .httpStatus(503, []))? = updates.values.last else {
                    return XCTFail("Expected final HTTP error")
                }
            }
            XCTAssertEqual(StatusRetryProtocol.requests.count, 5)
            XCTAssertTrue(fixture.isQueueEmpty)
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(StatusRetryProtocol.requests.count, 5, "No sixth attempt: \(reply)")
        }
    }

    func testObserverReportsPermanentRetryRejection() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let observation = PushStatusRetryObservation(siteToken: "site", queue: fixture.queue)
        let updates = RetryUpdatesRecorder()
        observation.onUpdate = { updates.append($0) }
        defer { withExtendedLifetime(observation) {} }
        StatusRetryProtocol.reset([.http(500), .http(403)])
        fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site")
        await waitUntil {
            if case .rejected(_, .httpStatus(403, []))? = updates.values.last { return true }
            return false
        }
        XCTAssertEqual(StatusRetryProtocol.requests.count, 2)
        XCTAssertTrue(fixture.isQueueEmpty)
    }

    func testLateObserversReceiveSnapshotAndUnsubscribeIndependently() async {
        let fixture = makeFixture(baseDelay: 3_600)
        defer { fixture.cleanUp() }
        StatusRetryProtocol.reset([.http(500)])
        let queued = expectation(description: "Status queued")
        fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site") { _ in queued.fulfill() }
        await fulfillment(of: [queued], timeout: 2)
        let first = PushStatusRetryObservation(siteToken: "site", queue: fixture.queue)
        let second = PushStatusRetryObservation(siteToken: "site", queue: fixture.queue)
        let otherSite = PushStatusRetryObservation(siteToken: "other", queue: fixture.queue)
        let firstUpdates = RetryUpdatesRecorder()
        let secondUpdates = RetryUpdatesRecorder()
        let otherUpdates = RetryUpdatesRecorder()
        first.onUpdate = { firstUpdates.append($0) }
        second.onUpdate = { secondUpdates.append($0) }
        otherSite.onUpdate = { otherUpdates.append($0) }
        defer { withExtendedLifetime((first, second, otherSite)) {} }
        await waitUntil { firstUpdates.values.count == 1 && secondUpdates.values.count == 1 }
        guard case .pending(let event, 1, let date)? = firstUpdates.values.first else {
            return XCTFail("Expected snapshot of pending status")
        }
        XCTAssertEqual(event.pushID, "push")
        XCTAssertGreaterThan(date, Date())
        first.onUpdate = nil
        StatusRetryProtocol.setReplies([.http(204)])
        let succeeded = expectation(description: "Duplicate report succeeded")
        fixture.reporter.reportStatus(.delivered, pushId: "push", siteToken: "site") { result in
            guard case .success = result else { return XCTFail("Expected successful duplicate report") }
            succeeded.fulfill()
        }
        await fulfillment(of: [succeeded], timeout: 2)
        await waitUntil { secondUpdates.values.count == 2 }
        XCTAssertEqual(StatusRetryProtocol.requests.count, 2)
        XCTAssertTrue(fixture.isQueueEmpty)
        XCTAssertEqual(secondUpdates.values.last, .delivered(event))
        XCTAssertEqual(firstUpdates.values.count, 1)
        XCTAssertTrue(otherUpdates.values.isEmpty)
    }

    private func makeFixture(baseDelay: TimeInterval = 0.01) -> Fixture {
        let session = makeSession()
        let databaseURL = temporaryURL()
        let storage = PushStatusRetryStorage(databaseURL: databaseURL)
        let queue = PushStatusRetryQueue(storage: storage, baseDelay: baseDelay, monitorsNetwork: false)
        return Fixture(session: session, reporter: .init(session: session, retryQueue: queue), queue: queue,
                       storage: storage, databaseURL: databaseURL)
    }

    private func temporaryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PushStatusReporterTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatusRetryProtocol.self]
        return URLSession(configuration: config)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private struct Fixture {
        let session: URLSession
        let reporter: PushStatusReporter
        let queue: PushStatusRetryQueue
        let storage: PushStatusRetryStorage
        let databaseURL: URL
        var isQueueEmpty: Bool {
            (try? storage.loadPending().isEmpty) == true
        }
        func cleanUp() {
            session.invalidateAndCancel()
        }
    }
}

private final class RetryUpdatesRecorder {
    private let lock = NSLock()
    private var stored: [PushStatusRetryUpdate] = []
    var values: [PushStatusRetryUpdate] { lock.withLock { stored } }
    func append(_ update: PushStatusRetryUpdate) { lock.withLock { stored.append(update) } }
}

private final class StatusRetryProtocol: URLProtocol {
    enum Reply {
        case http(Int, retryAfter: String? = nil)
        case offline
        case nonHTTP
    }
    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var captured: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { captured } }
    static func reset(_ replies: [Reply]) {
        lock.withLock { self.replies = replies; captured = [] }
    }
    static func setReplies(_ replies: [Reply]) { lock.withLock { self.replies = replies } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        let reply = Self.lock.withLock {
            Self.captured.append(captured)
            return Self.replies.count > 1 ? Self.replies.removeFirst() : Self.replies.first ?? .http(204)
        }
        let response: URLResponse
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case .nonHTTP:
            response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        case .http(let status, let retryAfter):
            response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: retryAfter.map { ["Retry-After": $0] }
            )!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
