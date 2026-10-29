import Foundation
import UserNotifications
import XCTest
@testable import PushNotificationExtension

final class ExtensionNetworkObserverTests: XCTestCase {
    func testStatusAndImageRequestsAreObservedWithAnExtensionOnlyImport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExtensionObserverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("observer-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let observed = expectation(description: "Status and image completion events")
        observed.expectedFulfillmentCount = 2
        let observer = ExtensionNetworkObserver(completed: observed)
        let handler = PushNotificationHandler(
            siteToken: "test-site", session: session,
            retryQueue: PushStatusRetryQueue(storage: .init(databaseURL: databaseURL), baseDelay: 3_600, monitorsNetwork: false),
            networkObserver: observer
        )
        let content = UNMutableNotificationContent()
        content.userInfo = ["r_group_push": true, "push_id": "app_1", "image_url": "https://observer.test/image.png"]
        let request = UNNotificationRequest(identifier: "observed", content: content, trigger: nil)
        let enriched = expectation(description: "Notification handling completes")
        XCTAssertTrue(handler.handle(request: request, content: content) { _ in enriched.fulfill() })
        await fulfillment(of: [observed, enriched], timeout: 3)
        let starts = observer.starts
        let finishes = observer.finishes
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(Set(starts.map(\.id)), Set(finishes.map(\.id)))
        let image = try XCTUnwrap(starts.first { $0.request.url?.path == "/image.png" })
        let imageResult = try XCTUnwrap(finishes.first { $0.id == image.id })
        XCTAssertNil(imageResult.responseBody)
        XCTAssertEqual((imageResult.error as? URLError)?.code, .notConnectedToInternet)
        let status = try XCTUnwrap(starts.first { $0.id != image.id })
        XCTAssertEqual(status.request.httpMethod, "POST")
        XCTAssertEqual(status.request.value(forHTTPHeaderField: "X-Site-Token"), "test-site")
        let statusResult = try XCTUnwrap(finishes.first { $0.id == status.id })
        XCTAssertEqual((statusResult.response as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertNil(statusResult.error)
    }
}

private final class ExtensionNetworkObserver: CrmSdkNetworkObserver, @unchecked Sendable {
    private let completed: XCTestExpectation
    private let lock = NSLock()
    private var recordedStarts: [CrmSdkNetworkRequest] = []
    private var recordedFinishes: [CrmSdkNetworkResponse] = []
    var starts: [CrmSdkNetworkRequest] { lock.withLock { recordedStarts } }
    var finishes: [CrmSdkNetworkResponse] { lock.withLock { recordedFinishes } }
    init(completed: XCTestExpectation) { self.completed = completed }
    func requestDidStart(_ event: CrmSdkNetworkRequest) { lock.withLock { recordedStarts.append(event) } }
    func requestDidComplete(_ event: CrmSdkNetworkResponse) {
        lock.withLock { recordedFinishes.append(event) }
        completed.fulfill()
    }
}

private final class ExtensionObserverURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/image.png" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
