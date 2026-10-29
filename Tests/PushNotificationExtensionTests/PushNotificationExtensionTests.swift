import Foundation
import UserNotifications
import XCTest
@testable import PushNotificationExtension

final class PushNotificationExtensionTests: XCTestCase {
    private var session: URLSession!
    private var handler: PushNotificationHandler!
    private var retryQueue: PushStatusRetryQueue!

    override func setUp() {
        super.setUp()
        ExtensionURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExtensionURLProtocol.self]
        session = URLSession(configuration: configuration)
        let retryDatabaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PushNotificationExtensionTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: retryDatabaseURL) }
        retryQueue = PushStatusRetryQueue(storage: .init(databaseURL: retryDatabaseURL), baseDelay: 3_600, monitorsNetwork: false)
        handler = PushNotificationHandler(
            siteToken: "test-site", session: session,
            retryQueue: retryQueue
        )
    }

    override func tearDown() {
        session.invalidateAndCancel()
        handler = nil
        session = nil
        retryQueue = nil
        super.tearDown()
    }

    func testUnrelatedNotificationsAreLeftToIntegrator() async {
        let content = UNMutableNotificationContent()
        content.title = "Own notification"
        content.userInfo = ["provider": "other"]
        let completion = expectation(description: "Unrelated notification must not be enriched")
        completion.isInverted = true
        XCTAssertFalse(handler.handle(request: request(content), content: content) { _ in completion.fulfill() })
        await fulfillment(of: [completion], timeout: 0.1)
        XCTAssertEqual(content.title, "Own notification")
        XCTAssertEqual(content.userInfo["provider"] as? String, "other")
        XCTAssertEqual(ExtensionURLProtocol.requests.count, 0)
    }

    func testDeliveryUsesCustomBackend() async throws {
        handler = PushNotificationHandler(
            siteToken: "test-site", baseURL: "http://localhost:8080/proxy/", session: session, retryQueue: retryQueue
        )
        let content = crmContent()
        let reported = expectation(description: "Custom backend received status")
        XCTAssertTrue(handler.handle(request: request(content), content: content) { _ in reported.fulfill() })
        await fulfillment(of: [reported], timeout: 3)
        XCTAssertEqual(ExtensionURLProtocol.requests.first?.url?.absoluteString,
                       "http://localhost:8080/proxy/api/client/v1/push-tokens/set-status")
    }

    func testEnrichSendsStatusAndMarksContent() async throws {
        let content = crmContent()
        content.userInfo["r_group_category"] = "news"
        let reported = expectation(description: "Delivery reported")
        XCTAssertTrue(handler.handle(request: request(content), content: content) { result in
            XCTAssertEqual(result.categoryIdentifier, "news")
            XCTAssertEqual(result.userInfo["retailcrm_delivered_by_extension"] as? Bool, true)
            XCTAssertEqual(result.userInfo["push_id"] as? String, "app_1")
            reported.fulfill()
        })
        await fulfillment(of: [reported], timeout: 3)
        XCTAssertEqual(content.userInfo["retailcrm_delivered_by_extension"] as? Bool, true)
        XCTAssertEqual(content.userInfo["push_id"] as? String, "app_1")
        let captured = try XCTUnwrap(ExtensionURLProtocol.requests.first)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.url?.absoluteString, "https://c.retailcrm.tech/api/client/v1/push-tokens/set-status")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "X-Site-Token"), "test-site")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData(captured)) as? [String: Any])
        XCTAssertEqual(body["push_id"] as? String, "app_1")
        XCTAssertEqual(body["status"] as? String, "delivered")
        XCTAssertGreaterThan(try XCTUnwrap((body["changed_at"] as? NSNumber)?.int64Value), 0)
        XCTAssertEqual(ExtensionURLProtocol.requests.count, 1)
    }

    func testDeliveryFailureDoesNotPreventEnrichment() async {
        ExtensionURLProtocol.reset(error: URLError(.notConnectedToInternet))
        let content = crmContent()
        content.userInfo["r_group_category"] = "news"
        let request = request(content)
        let enriched = expectation(description: "Content enriched despite delivery failure")
        XCTAssertTrue(handler.handle(request: request, content: content) { result in
            XCTAssertEqual(result.categoryIdentifier, "news")
            enriched.fulfill()
        })
        await fulfillment(of: [enriched], timeout: 3)
        XCTAssertEqual(ExtensionURLProtocol.requests.count, 1)
    }

    func testImageDownloadFailureStillReturnsNotification() async {
        ExtensionURLProtocol.reset(error: URLError(.notConnectedToInternet))
        let content = crmContent()
        content.userInfo["image_url"] = "https://example.com/image.png"
        let enriched = expectation(description: "Notification returned without image")
        XCTAssertTrue(handler.handle(request: request(content), content: content) { result in
            XCTAssertEqual(result.body, "Message")
            XCTAssertTrue(result.attachments.isEmpty)
            enriched.fulfill()
        })
        await fulfillment(of: [enriched], timeout: 3)
        XCTAssertEqual(ExtensionURLProtocol.requests.compactMap(\.httpMethod).sorted(), ["GET", "POST"])
    }

    func testButtonsKeepActionIdentifiersAndURLs() async throws {
        try XCTSkipUnless(Bundle.main.bundleURL.pathExtension == "app", "Requires an iOS application test host")
        let content = crmContent()
        content.userInfo["buttons"] = #"[{"title":"Buy","value":"app://buy"}]"#
        let enriched = expectation(description: "Buttons added")
        XCTAssertTrue(handler.handle(request: request(content), content: content) { result in
            XCTAssertEqual(result.categoryIdentifier, "app_1")
            XCTAssertEqual(result.userInfo["push_button_action_urls"] as? [String: String], ["app_1_0": "app://buy"])
            enriched.fulfill()
        })
        await fulfillment(of: [enriched], timeout: 3)
        let categories = await UNUserNotificationCenter.current().notificationCategories()
        let category = try XCTUnwrap(categories.first { $0.identifier == "app_1" })
        XCTAssertEqual(category.actions.map(\.identifier), ["app_1_0"])
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories.filter { $0.identifier != "app_1" }))
        XCTAssertEqual(ExtensionURLProtocol.requests.count, 1)
    }

    private func crmContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.body = "Message"
        content.userInfo = ["r_group_push": true, "push_id": "app_1"]
        return content
    }

    private func request(_ content: UNNotificationContent) -> UNNotificationRequest {
        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    private func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class ExtensionURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedRequests: [URLRequest] = []
    private static var responseError: Error?

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func reset(error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests = []
        responseError = error
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let error = Self.responseError
        Self.lock.unlock()
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
