import Foundation
import UserNotifications
import XCTest
@testable import Core
@testable import PushService
@testable import PushNotificationExtension

final class PushNetworkSessionTests: XCTestCase {
    func testExtensionSessionCompletesAndExposesStatusRetryUpdates() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let siteToken = UUID().uuidString
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PushNetworkSessionTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let handler = PushNotificationHandler(
            siteToken: siteToken, session: session,
            retryQueue: PushStatusRetryQueue(storage: .init(databaseURL: databaseURL), baseDelay: 3_600, monitorsNetwork: false)
        )
        let content = makeContent()
        let request = UNNotificationRequest(identifier: "extension", content: content, trigger: nil)
        let enriched = expectation(description: "Delivery and image requests finished")
        let queued = expectation(description: "Extension exposes retry updates")
        handler.onStatusRetryUpdate = { update in
            if case .queued(let event, _) = update {
                XCTAssertEqual(event.pushID, "app_1")
                XCTAssertEqual(event.status, .delivered)
                queued.fulfill()
            }
        }
        XCTAssertTrue(handler.handle(request: request, content: content) { _ in enriched.fulfill() })
        await fulfillment(of: [enriched, queued], timeout: 3)
    }

    func testPushServiceExposesStatusRetryUpdates() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PushNetworkSessionTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let queue = PushStatusRetryQueue(storage: .init(databaseURL: databaseURL), baseDelay: 3_600, monitorsNetwork: false)
        let handler = PushHandler(siteToken: "site", session: session, retryQueue: queue)
        let service = PushService(
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site")),
            pushHandler: handler
        )
        let queued = expectation(description: "PushService exposes queued status")
        service.onStatusRetryUpdate = { update in
            if case .queued(let event, _) = update {
                XCTAssertEqual(event.pushID, "app_1")
                XCTAssertEqual(event.status, .delivered)
                queued.fulfill()
            }
        }
        XCTAssertNotNil(service.onStatusRetryUpdate)
        let completed = expectation(description: "First attempt completed")
        XCTAssertTrue(handler.handleSilentNotification([
            "r_group_push": true, "push_id": "app_1", "aps": ["content-available": 1]
        ]) { _ in completed.fulfill() })
        await fulfillment(of: [queued, completed], timeout: 3)
        service.onStatusRetryUpdate = nil
        XCTAssertNil(service.onStatusRetryUpdate)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushSessionFailureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "r_group_push": true,
            "push_id": "app_1",
            "image_url": "https://example.com/\(UUID().uuidString).png"
        ]
        return content
    }
}

private final class PushSessionFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
