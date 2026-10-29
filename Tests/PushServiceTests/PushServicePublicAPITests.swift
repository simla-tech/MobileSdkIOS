import Foundation
import UserNotifications
import XCTest
@testable import PushService
@testable import PushNotificationExtension
@testable import Core

final class PushServicePublicAPITests: XCTestCase {

    func testPushStatusRequestBodyEncodesBackendPayload() throws {
        for hash: String? in [nil, "button-sha256"] {
            let body = PushStatusRequestBody(changedAt: 1_808_000_001, pushId: "mobile_123", status: .clicked, buttonHash: hash)
            let data = try JSONEncoder().encode(body)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let context = "buttonHash: \(hash ?? "nil")"
            XCTAssertEqual((json["changed_at"] as? NSNumber)?.int64Value, 1_808_000_001, context)
            XCTAssertEqual(json["push_id"] as? String, "mobile_123", context)
            XCTAssertEqual(json["status"] as? String, "clicked", context)
            XCTAssertEqual(json["button_hash"] as? String, hash, context)
            if hash == nil { XCTAssertNil(json["button_hash"], context) }
            XCTAssertNil(json["changedAt"], context)
            XCTAssertNil(json["pushId"], context)
            XCTAssertNil(json["buttonHash"], context)
        }
    }

    func testPushMessageParserMapsSDKPushPayload() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Order changed",
                    "body": "Order text"
                ]
            ],
            "r_group_push": "1",
            "r_group_category": " news ",
            "push_id": "mobile_123",
            "image_url": "https://example.com/image.png",
            "click_action": "https://example.com/order",
            "ca_orderId": "123",
            "ca_source": "push",
            "ca_empty": "",
            "ca_number": 42,
            "ca_": "ignored",
            "buttons": #"""
            [
                {"title":"Open order","value":"https://example.com/order"},
                {"title":"Support","value":"https://example.com/support"}
            ]
            """#
        ]

        let message = try XCTUnwrap(
            PushMessageParser.parse(
                userInfo: userInfo,
                title: "Order changed",
                body: "Order text"
            )
        )

        XCTAssertEqual(message.pushId, "mobile_123")
        XCTAssertEqual(message.title, "Order changed")
        XCTAssertEqual(message.body, "Order text")
        XCTAssertEqual(message.imageURL, URL(string: "https://example.com/image.png"))
        XCTAssertEqual(message.clickAction?.stringUrl, "https://example.com/order")
        XCTAssertEqual(message.rgCategory, "news")
        XCTAssertEqual(message.clickAction?.customAttributes, [
            "orderId": "123",
            "source": "push",
            "empty": "",
            "number": "42"
        ])
        XCTAssertEqual(message.buttons, [
            PushButton(
                title: "Open order",
                value: "https://example.com/order"
            ),
            PushButton(
                title: "Support",
                value: "https://example.com/support"
            )
        ])
    }

    func testPushMessageParserKeepsActionsWithoutScheme() throws {
        for isButton in [false, true] {
            var info: [AnyHashable: Any] = ["r_group_push": "1", "push_id": "mobile_123"]
            if isButton { info["buttons"] = #"[{"title":"Open order","value":"OPEN_ORDER"}]"# }
            else { info["click_action"] = "OPEN_ORDER" }
            let message = try XCTUnwrap(PushMessageParser.parse(userInfo: info))
            if isButton {
                XCTAssertEqual(message.buttons, [PushButton(title: "Open order", value: "OPEN_ORDER")])
            } else {
                XCTAssertEqual(message.clickAction?.stringUrl, "OPEN_ORDER")
            }
        }
    }

    func testPushHandlerResolvesDefaultButtonAndUnknownActions() throws {
        let message = try XCTUnwrap(PushMessageParser.parse(userInfo: [
            "r_group_push": "1", "push_id": "mobile_123", "click_action": "sample-shop://orders/75/",
            "buttons": #"[{"title":"Open order","value":"https://example.com/order"}]"#
        ]))
        let handler = PushHandler(siteToken: "site-token", retryQueue: isolatedRetryQueue())
        let cases: [(String, String?)] = [
            (UNNotificationDefaultActionIdentifier, "sample-shop://orders/75/"),
            ("mobile_123_0", "https://example.com/order"), ("OPEN_ORDER", nil)
        ]
        for (action, expected) in cases {
            XCTAssertEqual(handler.actionURLString(in: message, for: action), expected, action)
        }
    }

    func testPushMessageParserTreatsBlankRGCategoryAsAbsent() throws {
        let message = try XCTUnwrap(PushMessageParser.parse(userInfo: [
            "r_group_push": "1",
            "r_group_category": "   ",
            "push_id": "mobile_123"
        ]))

        XCTAssertNil(message.rgCategory)
    }

    func testPushMessageParserIgnoresNonSDKPushPayload() {
        let message = PushMessageParser.parse(userInfo: [
            "push_id": "mobile_123",
            "title": "Foreign push"
        ])

        XCTAssertNil(message)
    }

    func testPushMessageParserKeepsEmptyNotificationTitleAndBody() throws {
        let message = try XCTUnwrap(
            PushMessageParser.parse(
                userInfo: [
                    "r_group_push": "1",
                    "push_id": "mobile_123",
                    "title": "Fallback title",
                    "body": "Fallback body"
                ],
                title: "",
                body: ""
            )
        )

        XCTAssertEqual(message.title, "")
        XCTAssertEqual(message.body, "")
    }

    func testPushTokensRejectEmptyValues() {
        let cases: [(PushToken, PushServiceError)] = [(.fcm("   "), .emptyFCMToken), (.fid("   "), .emptyFID)]
        for (token, expected) in cases {
            XCTAssertThrowsError(try token.normalizedToken(), "\(token)") { error in
                XCTAssertEqual(error as? PushServiceError, expected)
            }
        }
    }

    func testRegistrarUsesCustomBackend() async throws {
        CapturingURLProtocol.reset()
        let registrar = PushTokenRegistrator(
            session: makeCapturingSession(),
            clientAPIEndpointURL: URL(string: "https://consultant.example.com/api/client/v1")!
        )
        let result = await registerTokenResult(
            registrar: registrar, .fcm("fcm-token"),
            customerIdentity: .init(customerId: 10, siteCustomerId: nil, siteCode: nil),
            siteToken: "site-token", firebaseProjectId: makeFirebaseProjectId(), categories: ["system"]
        )
        assertSuccess(result)
        XCTAssertEqual(CapturingURLProtocol.capturedRequest?.url?.absoluteString,
                       "https://consultant.example.com/api/client/v1/push-tokens")
    }

    func testDefaultRegistrarSendsPushTokenRequest() async throws {
        CapturingURLProtocol.reset()
        let registrar = PushTokenRegistrator(session: makeCapturingSession())

        let result = await registerTokenResult(
            registrar: registrar,
            .fcm("fcm-token"),
            customerIdentity: .init(customerId: 10, siteCustomerId: nil, siteCode: nil),
            siteToken: "site-token",
            firebaseProjectId: makeFirebaseProjectId(),
            categories: ["orders", "vip"]
        )

        assertSuccess(result)

        let request = try XCTUnwrap(CapturingURLProtocol.capturedRequest)
        XCTAssertEqual(
            request.url,
            URL(string: "https://c.retailcrm.tech/api/client/v1/push-tokens")
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Site-Token"), "site-token")

        let body = try decodeBody(from: request)
        XCTAssertEqual(body.customerId, 10)
        XCTAssertNil(body.customerExternalId)
        XCTAssertNil(body.crmSiteCode)
        XCTAssertEqual(body.token, "fcm-token")
        XCTAssertNil(body.fid)
        XCTAssertEqual(body.type, "firebase-project-id")
        XCTAssertEqual(body.deviceType, "ios")
        XCTAssertEqual(body.categories, ["orders", "vip"])
    }

    func testDefaultRegistrarMapsSiteIdentityToServerFields() async throws {
        CapturingURLProtocol.reset()
        let registrar = PushTokenRegistrator(session: makeCapturingSession())
        let result = await registerTokenResult(
            registrar: registrar,
            .fcm("fcm-token"),
            customerIdentity: .init(siteCustomerId: "customer-123", siteCode: "main"),
            siteToken: "site-token",
            firebaseProjectId: makeFirebaseProjectId(),
            categories: ["system"]
        )

        assertSuccess(result)

        let body = try decodeCapturedBody()
        XCTAssertNil(body.customerId)
        XCTAssertEqual(body.customerExternalId, "customer-123")
        XCTAssertEqual(body.crmSiteCode, "main")
    }

    func testDeliveryReportedByExtensionIsNotReportedAgainInApp() async throws {
        CapturingURLProtocol.reset()
        let session = makeCapturingSession()
        defer { session.invalidateAndCancel() }
        let extensionHandler = PushNotificationHandler(siteToken: "site-token", session: session, retryQueue: isolatedRetryQueue())
        let appHandler = PushHandler(siteToken: "site-token", session: session, retryQueue: isolatedRetryQueue())
        let content = UNMutableNotificationContent()
        content.userInfo = ["r_group_push": true, "push_id": "mobile_123"]
        let request = UNNotificationRequest(identifier: "delivery", content: content, trigger: nil)
        let reported = expectation(description: "Extension reports delivery")
        XCTAssertTrue(extensionHandler.handle(request: request, content: content) { _ in
            reported.fulfill()
        })
        await fulfillment(of: [reported], timeout: 3)
        XCTAssertEqual(CapturingURLProtocol.requestCount, 1)

        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(UNNotificationRequest(identifier: "foreground", content: content, trigger: nil), forKey: "request")
        archive.encode(Date(), forKey: "date")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        defer { decoder.finishDecoding() }
        let notification = try XCTUnwrap(UNNotification(coder: decoder))
        let handled = expectation(description: "App accepts existing delivery marker")
        XCTAssertTrue(appHandler.handleWillPresent(notification, completion: { result in
            assertSuccess(result)
            // The completion follows the request if a duplicate was accidentally sent.
            XCTAssertEqual(CapturingURLProtocol.requestCount, 1)
            handled.fulfill()
        }))
        await fulfillment(of: [handled], timeout: 3)
    }

    func testPushStatusReporterPreservesHTTPErrorResponses() async {
        let cases = [(400, #"{"error":"push_id is invalid"}"#, "push_id is invalid"),
                     (403, "forbidden", "forbidden"), (400, #"{"errors":[]}"#, #"{"errors":[]}"#)]
        for (status, body, message) in cases {
            CapturingURLProtocol.reset(statusCode: status, body: Data(body.utf8))
            let session = makeCapturingSession()
            defer { session.invalidateAndCancel() }
            let reporter = PushStatusReporter(session: session, retryQueue: isolatedRetryQueue())
            let result = await reportStatusResult(reporter: reporter, .clicked, pushId: "invalid", siteToken: "site-token")
            assertFailure(result, .httpStatus(status, [message]))
        }
    }

    func testDefaultRegistrarPreservesHTTPErrorResponses() async {
        let cases = [(400, #"{"errors":["crmSiteCode is required for customerExternalId"]}"#, "crmSiteCode is required for customerExternalId"),
                     (403, "forbidden", "forbidden"), (400, #"{"errors":[]}"#, #"{"errors":[]}"#)]
        for (status, body, message) in cases {
            CapturingURLProtocol.reset(statusCode: status, body: Data(body.utf8))
            let session = makeCapturingSession()
            defer { session.invalidateAndCancel() }
            let result = await registerTokenResult(
                registrar: PushTokenRegistrator(session: session), .fcm("fcm-token"),
                customerIdentity: .init(customerId: 10, siteCustomerId: nil, siteCode: nil),
                siteToken: "site-token", firebaseProjectId: makeFirebaseProjectId(), categories: ["system"]
            )
            assertFailure(result, .httpStatus(status, [message]))
            if case .failure(let error) = result {
                XCTAssertTrue(error.localizedDescription.contains(String(status)), body)
                XCTAssertTrue(error.localizedDescription.contains(message), body)
            }
        }
    }

}

private func makeFirebaseProjectId() -> String {
    "firebase-project-id"
}

private func makeCapturingSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapturingURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func assertSuccess(
    _ result: Result<PushToken, PushServiceError>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case let .failure(error) = result {
        XCTFail("Expected success, got \(error)", file: file, line: line)
    }
}

private func assertSuccess(
    _ result: Result<Void, PushStatusReportingError>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case let .failure(error) = result {
        XCTFail("Expected success, got \(error)", file: file, line: line)
    }
}

private func assertFailure(
    _ result: Result<PushToken, PushServiceError>,
    _ expectedError: PushServiceError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("Expected failure \(expectedError), got success", file: file, line: line)
    case let .failure(error):
        XCTAssertEqual(error, expectedError, file: file, line: line)
    }
}

private func assertFailure(
    _ result: Result<Void, PushStatusReportingError>,
    _ expectedError: PushStatusReportingError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("Expected failure \(expectedError), got success", file: file, line: line)
    case let .failure(error):
        XCTAssertEqual(error, expectedError, file: file, line: line)
    }
}

private func reportStatusResult(
    reporter: PushStatusReporter,
    _ status: PushNotificationStatus,
    pushId: String,
    siteToken: String
) async -> Result<Void, PushStatusReportingError> {
    await withCheckedContinuation { continuation in
        reporter.reportStatus(
            status,
            pushId: pushId,
            siteToken: siteToken
        ) { result in
            continuation.resume(returning: result)
        }
    }
}

private func registerTokenResult(
    registrar: PushTokenRegistrator,
    _ token: PushToken,
    customerIdentity: CrmSdkCustomerIdentity,
    siteToken: String,
    firebaseProjectId: String,
    categories: [String]
) async -> Result<PushToken, PushServiceError> {
    await withCheckedContinuation { continuation in
        registrar.registerToken(
            token,
            customerIdentity: customerIdentity,
            siteToken: siteToken,
            firebaseProjectId: firebaseProjectId,
            categories: categories
        ) { result in
            continuation.resume(returning: result)
        }
    }
}

private func decodeCapturedBody() throws -> PushTokenRequestBody {
    let request = try XCTUnwrap(CapturingURLProtocol.capturedRequest)
    return try decodeBody(from: request)
}

private func decodeBody(from request: URLRequest) throws -> PushTokenRequestBody {
    guard let body = request.httpBody ?? data(from: request.httpBodyStream) else {
        XCTFail("Expected captured request body")
        throw PushServiceError.invalidHTTPResponse("Missing request body")
    }

    return try JSONDecoder().decode(PushTokenRequestBody.self, from: body)
}

private func data(from stream: InputStream?) -> Data? {
    guard let stream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        guard readCount > 0 else {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

private final class CapturingURLProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var statusCode = 204
    private static var body = Data()

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    static var capturedRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }

    static func reset(statusCode: Int = 204, body: Data = Data()) {
        lock.lock()
        requests = []
        self.statusCode = statusCode
        self.body = body
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let statusCode = Self.statusCode
        let body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct PushTokenRequestBody: Decodable {
    let customerId: Int64?
    let customerExternalId: String?
    let crmSiteCode: String?
    let token: String?
    let fid: String?
    let type: String
    let deviceType: String
    let categories: [String]
}
