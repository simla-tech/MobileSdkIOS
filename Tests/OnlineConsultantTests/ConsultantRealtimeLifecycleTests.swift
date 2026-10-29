import UIKit
import XCTest
@testable import Core
@testable import OnlineConsultant

@MainActor
final class ConsultantRealtimeLifecycleTests: XCTestCase {
    func testForegroundRestoresSocketWithLatestCursorEvenWhenErrorRetriesAreDisabled() async throws {
        let fixture = makeFixture(inForeground: true, autoReconnect: false)
        defer { fixture.session.invalidateAndCancel() }
        fixture.controller.start()
        await waitUntil { fixture.socket.requests.count == 1 }
        fixture.socket.emit(#"{"type":"message","data":{"id":"1","content":"Hello","updated_at":"2026-10-27T10:00:00Z"}}"#)
        await waitUntil { fixture.controller.messages.count == 1 }

        fixture.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await waitUntil { fixture.socket.activeCount == 0 }
        XCTAssertEqual(fixture.controller.state, .ready(isAnonymous: true))
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil { fixture.socket.requests.count == 2 }
        XCTAssertEqual(fixture.socket.maximumActiveCount, 1)
        let request = try XCTUnwrap(fixture.socket.requests.last)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "updated_at" }?.value, "2026-10-27T10:00:00Z")
        XCTAssertEqual(query?.first { $0.name == "token" }?.value, "user-token")

        fixture.controller.sessionDidDisconnect()
        await waitUntil { fixture.controller.state == .idle && fixture.socket.activeCount == 0 }
        fixture.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await settle()
        XCTAssertEqual(fixture.socket.requests.count, 2)
    }

    func testConnectionCompletedInBackgroundWaitsForForeground() async {
        let fixture = makeFixture(inForeground: false)
        defer { fixture.session.invalidateAndCancel() }
        fixture.controller.start()
        await waitUntil { fixture.controller.state == .ready(isAnonymous: true) }
        XCTAssertTrue(fixture.socket.requests.isEmpty)
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil { fixture.socket.requests.count == 1 }
        fixture.controller.sessionDidDisconnect()
        await waitUntil { fixture.socket.activeCount == 0 }
    }

    func testBackgroundCancelsPendingErrorRetry() async {
        let fixture = makeFixture(inForeground: true, retryDelay: 0.2)
        defer { fixture.session.invalidateAndCancel() }
        fixture.controller.start()
        await waitUntil { fixture.socket.requests.count == 1 }
        fixture.socket.fail()
        await settle()
        fixture.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fixture.socket.requests.count, 1)
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil { fixture.socket.requests.count == 2 }
        fixture.controller.sessionDidDisconnect()
        await waitUntil { fixture.socket.activeCount == 0 }
    }

    func testErrorRetryRemainsEnabledInForeground() async {
        let fixture = makeFixture(inForeground: true, retryDelay: 0.01)
        defer { fixture.session.invalidateAndCancel() }
        fixture.controller.start()
        await waitUntil { fixture.socket.requests.count == 1 }
        fixture.socket.fail()
        await waitUntil { fixture.socket.requests.count == 2 }
        XCTAssertEqual(fixture.socket.maximumActiveCount, 1)
        fixture.controller.sessionDidDisconnect()
        await waitUntil { fixture.socket.activeCount == 0 }
    }

    func testIdleControllerDoesNotOpenSocketOnForeground() async {
        let fixture = makeFixture(inForeground: false)
        defer { fixture.session.invalidateAndCancel() }
        fixture.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await settle()
        XCTAssertTrue(fixture.socket.requests.isEmpty)
        XCTAssertEqual(fixture.controller.state, .idle)
    }

    private func makeFixture(
        inForeground: Bool, autoReconnect: Bool = true, retryDelay: TimeInterval = 3
    ) -> (controller: OnlineConsultantController, socket: LifecycleWebSocketEngine, center: NotificationCenter, session: URLSession) {
        let center = NotificationCenter()
        let lifecycle = ConsultantApplicationLifecycle(
            notificationCenter: center, initiallyInForeground: inForeground, initialForegroundSceneIDs: []
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LifecycleConnectProtocol.self]
        let session = URLSession(configuration: config)
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site"), session: session, userTokenStorage: LifecycleTokenStorage()
        )
        let socket = LifecycleWebSocketEngine()
        let client = OnlineConsultantClient(
            config: OnlineConsultantConfig(
                autoReconnectWebSocket: autoReconnect, webSocketReconnectDelay: retryDelay, initialMessagesLimit: 0
            ), sessionRuntime: runtime, webSocketEngine: socket
        )
        return (OnlineConsultantController(client: client, applicationLifecycle: lifecycle), socket, center, session)
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

private final class LifecycleWebSocketEngine: ConsultantWebSocketEngine {
    private let lock = NSLock()
    private var storedRequests: [ConsultantWebSocketRequest] = []
    private var continuations: [UUID: AsyncThrowingStream<ConsultantWebSocketEvent, Error>.Continuation] = [:]
    private var maximum = 0
    var requests: [ConsultantWebSocketRequest] { lock.withLock { storedRequests } }
    var activeCount: Int { lock.withLock { continuations.count } }
    var maximumActiveCount: Int { lock.withLock { maximum } }

    func open(_ request: ConsultantWebSocketRequest) -> AsyncThrowingStream<ConsultantWebSocketEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            lock.withLock {
                storedRequests.append(request)
                continuations[id] = continuation
                maximum = max(maximum, continuations.count)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }

    func emit(_ text: String) {
        lock.withLock { Array(continuations.values) }.forEach { $0.yield(.event(rawText: text)) }
    }

    func fail() {
        lock.withLock { Array(continuations.values) }.forEach { $0.finish(throwing: URLError(.networkConnectionLost)) }
    }
}

private final class LifecycleConnectProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"user":{"token":"user-token"},"session":{"id":1},"behaviour":{"widget":true}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class LifecycleTokenStorage: UserTokenStorage {
    func getUserToken(siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws -> String? { nil }
    func setUserToken(_ token: String?, siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws {}
}
