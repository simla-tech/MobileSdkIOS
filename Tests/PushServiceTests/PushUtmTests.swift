import Foundation
import UserNotifications
import XCTest
@testable import Core
@testable import PushService

@MainActor
final class PushUtmTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CrmUtmAttributionStorage.shared.clear()
    }

    override func tearDown() {
        CrmUtmAttributionStorage.shared.clear()
        super.tearDown()
    }

    func testOpenNormalizesUtmBeforeCallbackEvenWhenStatusRequestFails() throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = makeService(session: session)
        let response = try makeResponse(userInfo: [
            "r_group_push": true, "push_id": "app_1",
            "utm_source": " push ", "utm_medium": "mobile", "utm_campaign": "sale",
            "utm_term": "shoes", "utm_content": "  "
        ])
        let expected = CrmUtmAttribution(source: "push", medium: "mobile", campaign: "sale", term: "shoes")
        let opened = expectation(description: "Open callback sees UTM")
        service.onNotificationOpen = { _ in
            XCTAssertEqual(CrmUtmAttributionStorage.shared.load(), expected)
            opened.fulfill()
        }
        let finished = expectation(description: "Response completed")
        let failed = expectation(description: "Status request fails")
        XCTAssertTrue(service.handleDidReceive(response, withCompletionHandler: {
            finished.fulfill()
        }, completion: { result in
            if case .success = result { XCTFail("Expected offline error") }
            failed.fulfill()
        }))
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load(), expected)
        wait(for: [opened, finished, failed], timeout: 3)
    }

    func testOnlyOpensReplaceUtmAndEmptyValuesKeepPreviousAttribution() throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = makeService(session: session)
        let finished = expectation(description: "Responses completed")
        finished.expectedFulfillmentCount = 5
        let failed = expectation(description: "Status requests fail")
        failed.expectedFulfillmentCount = 5
        func handle(_ userInfo: [AnyHashable: Any], action: String = UNNotificationDefaultActionIdentifier) throws {
            let response = try makeResponse(userInfo: userInfo, actionIdentifier: action)
            XCTAssertTrue(service.handleDidReceive(response, withCompletionHandler: {
                finished.fulfill()
            }, completion: { result in
                if case .success = result { XCTFail("Expected offline error") }
                failed.fulfill()
            }))
        }
        var userInfo: [AnyHashable: Any] = ["r_group_push": true, "push_id": "app_1", "utm_campaign": "first"]
        try handle(userInfo)
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load()?.campaign, "first")
        userInfo["utm_campaign"] = "second"
        userInfo["buttons"] = #"[{"title":"Buy","value":"app://buy"}]"#
        try handle(userInfo, action: UNNotificationDismissActionIdentifier)
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load()?.campaign, "first")
        try handle(userInfo, action: "app_1_0")
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load(), CrmUtmAttribution(campaign: "second"))
        userInfo.removeValue(forKey: "utm_campaign")
        try handle(userInfo)
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load()?.campaign, "second")
        userInfo["utm_source"] = "  "
        try handle(userInfo)
        XCTAssertEqual(CrmUtmAttributionStorage.shared.load()?.campaign, "second")
        wait(for: [finished, failed], timeout: 3)
    }

    func testUnrelatedNotificationDoesNotSaveUtm() throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = makeService(session: session)
        let response = try makeResponse(userInfo: ["push_id": "app_1", "utm_campaign": "other"])
        XCTAssertFalse(service.handleDidReceive(response, withCompletionHandler: {
            XCTFail("Unrelated notification must not be handled")
        }))
        XCTAssertNil(CrmUtmAttributionStorage.shared.load())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UtmFailureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeService(session: URLSession) -> PushService {
        PushService(
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "test")),
            pushHandler: PushHandler(siteToken: "test", session: session, retryQueue: isolatedRetryQueue())
        )
    }

    private func makeResponse(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String = UNNotificationDefaultActionIdentifier
    ) throws -> UNNotificationResponse {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let notificationArchive = NSKeyedArchiver(requiringSecureCoding: true)
        notificationArchive.encode(request, forKey: "request")
        notificationArchive.encode(Date(), forKey: "date")
        notificationArchive.finishEncoding()
        let notificationDecoder = try NSKeyedUnarchiver(forReadingFrom: notificationArchive.encodedData)
        defer { notificationDecoder.finishDecoding() }
        let notification = try XCTUnwrap(UNNotification(coder: notificationDecoder))

        let responseArchive = NSKeyedArchiver(requiringSecureCoding: true)
        responseArchive.encode(notification, forKey: "notification")
        responseArchive.encode(actionIdentifier, forKey: "actionIdentifier")
        responseArchive.finishEncoding()
        let responseDecoder = try NSKeyedUnarchiver(forReadingFrom: responseArchive.encodedData)
        defer { responseDecoder.finishDecoding() }
        return try XCTUnwrap(UNNotificationResponse(coder: responseDecoder))
    }
}

private final class UtmFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
