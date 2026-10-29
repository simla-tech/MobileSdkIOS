import UIKit
import XCTest
@testable import Core
@testable import OnlineConsultant

@MainActor
final class ConsultantMessageRetryTests: XCTestCase {
    func testTextRetryKeepsOneMessageAndCanBeRetriedAfterAnotherFailure() async throws {
        let fixture = try await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        await expectFailure { try await fixture.controller.sendMessage("Hello") }
        let local = try XCTUnwrap(fixture.controller.messages.first)
        let id = try XCTUnwrap(local.id?.value)
        XCTAssertTrue(local.canRetrySending)

        await expectFailure { try await fixture.controller.retryMessage(id: id) }
        XCTAssertEqual(fixture.controller.messages.count, 1)
        XCTAssertEqual(fixture.controller.messages.first?.id?.value, id)
        XCTAssertEqual(fixture.controller.messages.first?.status, .failed)

        fixture.engine.configure(status: 200)
        try await fixture.controller.retryMessage(id: id)
        XCTAssertEqual(fixture.controller.messages.count, 1)
        XCTAssertEqual(fixture.controller.messages.first?.id?.value, "server-3")
        XCTAssertEqual(fixture.controller.messages.first?.content, "Hello")
        XCTAssertEqual(fixture.controller.messages.first?.status, .sent)
        XCTAssertEqual(fixture.engine.requests.count, 3)
        XCTAssertEqual(Set(try fixture.engine.requests.map(canonicalBody)).count, 1)
        try await fixture.controller.retryMessage(id: "server-3")
        XCTAssertEqual(fixture.engine.requests.count, 3)
    }

    func testAttachmentRetryReusesUploadedItemsAndDoesNotResendOtherMessages() async throws {
        let fixture = try await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let preview = Data([1, 2, 3])
        let attachments = [
            InputAttachment(fileName: "photo.png", contentType: "image/png", previewData: preview,
                            messageType: "image", status: .uploaded(fileID: FlexibleID("image-id"))),
            InputAttachment(fileName: "document.pdf", status: .uploaded(fileID: FlexibleID("file-id")))
        ]
        await expectFailure {
            try await fixture.controller.sendMessage("Caption", attachments: attachments)
        }
        XCTAssertEqual(fixture.controller.messages.count, 3)
        let failed = fixture.controller.messages
        fixture.engine.configure(status: 200)
        for message in failed {
            let id = try XCTUnwrap(message.id?.value)
            try await fixture.controller.retryMessage(id: id)
            XCTAssertEqual(fixture.controller.messages.count, 3)
        }
        let requests = fixture.engine.requests
        XCTAssertEqual(requests.count, 6)
        for index in 0..<3 {
            XCTAssertEqual(try canonicalBody(requests[index]), try canonicalBody(requests[index + 3]))
        }
        XCTAssertTrue(fixture.controller.messages.allSatisfy { $0.status == .sent })
        let image = try XCTUnwrap(fixture.controller.messages.first { $0.messageType == .image })
        XCTAssertEqual(image.items?.first?.id, "image-id")
        XCTAssertEqual(image.items?.first?.url, "data:image/png;base64,\(preview.base64EncodedString())")
    }

    func testRepeatedRetryWhileSendingDoesNotSendTwice() async throws {
        let fixture = try await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        await expectFailure { try await fixture.controller.sendMessage("Hello") }
        let id = try XCTUnwrap(fixture.controller.messages.first?.id?.value)
        fixture.engine.configure(status: 200, hold: true)
        let sending = Task { try await fixture.controller.retryMessage(id: id) }
        await waitUntil { fixture.engine.hasPendingRequest }
        XCTAssertEqual(fixture.controller.messages.first?.status, .sending)
        try await fixture.controller.retryMessage(id: id)
        XCTAssertEqual(fixture.engine.requests.count, 2)
        fixture.engine.completePendingRequest()
        try await sending.value
        XCTAssertEqual(fixture.controller.messages.first?.status, .sent)
    }

    func testFailedAttachmentHasContextMenuWithoutCopyableText() throws {
        let view = ConsultantView()
        let message = ConsultantMessage(
            id: FlexibleID("_local_test"), items: [MessageItem(id: "file-id")],
            fromMe: true, messageType: .file, status: .failed
        )
        XCTAssertNil(message.clipboardText)
        view.setMessages([message])
        let collection = try XCTUnwrap(
            view.subviews.flatMap(\.subviews).compactMap { $0 as? UICollectionView }.first
        )
        XCTAssertNotNil(view.collectionView(
            collection, contextMenuConfigurationForItemAt: IndexPath(item: 0, section: 0), point: .zero
        ))
        for status in [MessageStatus.sending, .sent, .seen] {
            view.setMessages([message.applyingStatus(status)])
            XCTAssertNil(view.collectionView(
                collection, contextMenuConfigurationForItemAt: IndexPath(item: 0, section: 0), point: .zero
            ))
        }
        XCTAssertFalse(ConsultantMessage(
            id: FlexibleID("1"), content: "Incoming", fromMe: false, messageType: .text, status: .failed
        ).canRetrySending)
    }

    func testSendAndRetryFailuresDoNotPresentAlert() async throws {
        let fixture = try await makeFixture()
        defer { fixture.session.invalidateAndCancel() }
        let screen = OnlineConsultantViewController(controller: fixture.controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = screen
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        screen.loadViewIfNeeded()
        screen.consultantView.onSendMessage?("Hello")
        await waitUntil { fixture.controller.messages.first?.status == .failed }
        let id = try XCTUnwrap(fixture.controller.messages.first?.id?.value)
        XCTAssertNil(screen.presentedViewController)
        screen.consultantView.onRetryMessage?(id)
        await waitUntil { fixture.engine.requests.count == 2 && fixture.controller.messages.first?.status == .failed }
        XCTAssertNil(screen.presentedViewController)
        XCTAssertEqual(fixture.controller.messages.count, 1)
    }

    private func makeFixture() async throws -> (
        controller: OnlineConsultantController, engine: RetryNetworkEngine, session: URLSession
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetryConnectProtocol.self]
        let session = URLSession(configuration: configuration)
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site"), session: session, userTokenStorage: RetryTokenStorage()
        )
        let engine = RetryNetworkEngine()
        let controller = OnlineConsultantController(
            client: OnlineConsultantClient(
                config: OnlineConsultantConfig(initialMessagesLimit: 0), sessionRuntime: runtime, networkEngine: engine
            ),
            applicationLifecycle: ConsultantApplicationLifecycle(
                notificationCenter: NotificationCenter(), initiallyInForeground: false, initialForegroundSceneIDs: []
            )
        )
        controller.start()
        await waitUntil { controller.state == .ready(isAnonymous: true) }
        return (controller, engine, session)
    }

    private func expectFailure(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected sending to fail")
        } catch {}
    }

    private func canonicalBody(_ request: ConsultantHTTPRequest) throws -> Data {
        let body = try XCTUnwrap(request.body)
        return try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: body), options: .sortedKeys
        )
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private final class RetryNetworkEngine: ConsultantNetworkEngine {
    private let lock = NSLock()
    private var storedRequests: [ConsultantHTTPRequest] = []
    private var status = 500
    private var hold = false
    private var pending: CheckedContinuation<ConsultantHTTPResponse, Never>?
    var requests: [ConsultantHTTPRequest] { lock.withLock { storedRequests } }
    var hasPendingRequest: Bool { lock.withLock { pending != nil } }

    func configure(status: Int, hold: Bool = false) {
        lock.withLock { self.status = status; self.hold = hold }
    }

    func getJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(statusCode: 200, body: Data(#"{"url":"https://example.test/file"}"#.utf8))
    }

    func postJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        let (status, hold) = lock.withLock {
            storedRequests.append(request)
            return (self.status, self.hold)
        }
        if hold {
            return await withCheckedContinuation { continuation in
                lock.withLock { pending = continuation }
            }
        }
        return response(status: status)
    }

    func postRaw(_ request: ConsultantRawHTTPRequest) async throws -> ConsultantHTTPResponse {
        XCTFail("Retry must not upload attachments again")
        return response(status: 500)
    }

    func completePendingRequest() {
        let continuation = lock.withLock { () -> CheckedContinuation<ConsultantHTTPResponse, Never>? in
            defer { pending = nil }
            return pending
        }
        continuation?.resume(returning: response(status: 200))
    }

    private func response(status: Int) -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(
            statusCode: status,
            body: Data("{\"message\":{\"id\":\"server-\(requests.count)\",\"time\":\"2026-10-28T10:00:00Z\",\"status\":\"sent\"}}".utf8)
        )
    }
}

private final class RetryConnectProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"user":{"token":"user-token"},"session":{"id":1},"behaviour":{"widget":true}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class RetryTokenStorage: UserTokenStorage {
    func getUserToken(siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws -> String? { nil }
    func setUserToken(_ token: String?, siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws {}
}
