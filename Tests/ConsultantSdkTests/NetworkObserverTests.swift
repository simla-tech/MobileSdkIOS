import Foundation
import XCTest
import Core

final class NetworkObserverTests: XCTestCase {
    override func tearDown() {
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60)
        super.tearDown()
    }

    func testConfigurationDefaultsAndObserver() async {
        XCTAssertNil(CrmSdkConfig(siteToken: "site").networkObserver)
        let observer = RecordingNetworkObserver(completed: expectation(description: "unused"))
        observer.completed.isInverted = true
        let config = CrmSdkConfig(siteToken: "site", networkObserver: observer)
        XCTAssertTrue(config.networkObserver as? RecordingNetworkObserver === observer)
        XCTAssertFalse(observer.collectsMetrics)
        await fulfillment(of: [observer.completed], timeout: 0.01)
    }

    func testHTTPEventsContainPreparedRequestBodyResponseAndUniqueIDs() async throws {
        let completed = expectation(description: "Three completed requests")
        completed.expectedFulfillmentCount = 3
        let observer = RecordingNetworkObserver(completed: completed)
        NetworkSession.configure(requestTimeout: 17, resourceTimeout: 30, observer: observer)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for path in ["ok", "bad", "ok"] {
            var request = URLRequest(url: URL(string: "https://observer.test/\(path)")!)
            request.httpMethod = "POST"
            request.httpBody = Data("request-body".utf8)
            request.setValue("test-header", forHTTPHeaderField: "X-Test")
            _ = try await NetworkSession.data(for: request, in: session)
        }
        await fulfillment(of: [completed], timeout: 3)
        let starts = observer.starts
        let finishes = observer.finishes
        XCTAssertEqual(Set(starts.map(\.id)).count, 3)
        XCTAssertEqual(starts.map(\.id), finishes.map(\.id))
        XCTAssertEqual(observer.eventOrder, ["start", "complete", "start", "complete", "start", "complete"])
        XCTAssertEqual(finishes.map { ($0.response as? HTTPURLResponse)?.statusCode }, [200, 400, 200])
        for start in starts {
            XCTAssertEqual(start.request.httpMethod, "POST")
            XCTAssertEqual(start.request.timeoutInterval, 17)
            XCTAssertEqual(start.request.httpBody, Data("request-body".utf8))
            XCTAssertEqual(start.request.value(forHTTPHeaderField: "X-Test"), "test-header")
            XCTAssertLessThan(abs(start.startedAt.timeIntervalSinceNow), 10)
        }
        for finish in finishes {
            XCTAssertEqual(finish.responseBody, Data("response-body".utf8))
            XCTAssertNil(finish.error)
            XCTAssertGreaterThanOrEqual(finish.duration, 0)
        }
        XCTAssertTrue(observer.metricsIDs.isEmpty)
    }

    func testFailureTimeoutAndCancellationEmitTheSameErrorsAsTheCaller() async throws {
        let completed = expectation(description: "Three failed requests")
        completed.expectedFulfillmentCount = 3
        let observer = RecordingNetworkObserver(completed: completed)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for (path, code) in [("offline", URLError.notConnectedToInternet), ("slow-timeout", .timedOut), ("slow-cancel", .cancelled)] {
            NetworkSession.configure(requestTimeout: 10, resourceTimeout: path == "slow-timeout" ? 0.05 : 30, observer: observer)
            let task = Task {
                try await NetworkSession.data(for: URLRequest(url: URL(string: "https://observer.test/\(path)")!), in: session)
            }
            if code == .cancelled {
                try await Task.sleep(nanoseconds: 50_000_000)
                task.cancel()
            }
            do {
                _ = try await task.value
                XCTFail("Expected \(code)")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, code)
            }
        }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(observer.finishes.map { ($0.error as? URLError)?.code }, [.notConnectedToInternet, .timedOut, .cancelled])
        XCTAssertEqual(observer.starts.map(\.id), observer.finishes.map(\.id))
        XCTAssertTrue(observer.finishes.allSatisfy { $0.response == nil })
    }

    func testMetricsAreCorrelatedAndSessionDelegateStillReceivesThem() async throws {
        let completed = expectation(description: "Completed request")
        let metrics = expectation(description: "Observer metrics")
        let forwardedMetrics = expectation(description: "Session delegate metrics")
        let observer = RecordingNetworkObserver(completed: completed, metrics: metrics)
        let delegate = MetricsSessionDelegate(received: forwardedMetrics)
        let session = makeSession(delegate: delegate)
        defer { session.invalidateAndCancel() }
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60, observer: observer)
        _ = try await NetworkSession.data(for: URLRequest(url: URL(string: "https://observer.test/ok")!), in: session)
        await fulfillment(of: [completed, metrics, forwardedMetrics], timeout: 3)
        XCTAssertEqual(observer.metricsIDs, observer.starts.map(\.id))
    }

    func testDownloadFailuresAreObservedWithoutAResponseBody() async {
        let completed = expectation(description: "Download failed")
        let observer = RecordingNetworkObserver(completed: completed)
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60, observer: observer)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let callerCompleted = expectation(description: "Download caller")
        NetworkSession.downloadTask(with: URL(string: "https://observer.test/offline")!, in: session) { _, _, error in
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            callerCompleted.fulfill()
        }.resume()
        await fulfillment(of: [completed, callerCompleted], timeout: 3)
        XCTAssertEqual(observer.starts.map(\.id), observer.finishes.map(\.id))
        XCTAssertNil(observer.finishes.first?.responseBody)
        XCTAssertEqual((observer.finishes.first?.error as? URLError)?.code, .notConnectedToInternet)
    }

    func testReentrantObserverDoesNotBlockOrDeadlockRequests() async throws {
        let completed = expectation(description: "Reentrant observer")
        let observer = ReentrantNetworkObserver(completed: completed)
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60, observer: observer)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        _ = try await NetworkSession.data(for: URLRequest(url: URL(string: "https://observer.test/ok")!), in: session)
        await fulfillment(of: [completed], timeout: 3)
    }

    private func makeSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ObserverURLProtocol.self]
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

private final class RecordingNetworkObserver: CrmSdkNetworkObserver, @unchecked Sendable {
    let completed: XCTestExpectation
    private let metrics: XCTestExpectation?
    var collectsMetrics: Bool { metrics != nil }
    private let lock = NSLock()
    private var recordedStarts: [CrmSdkNetworkRequest] = []
    private var recordedFinishes: [CrmSdkNetworkResponse] = []
    private var recordedMetricsIDs: [UUID] = []
    private var order: [String] = []
    var starts: [CrmSdkNetworkRequest] { lock.withLock { recordedStarts } }
    var finishes: [CrmSdkNetworkResponse] { lock.withLock { recordedFinishes } }
    var metricsIDs: [UUID] { lock.withLock { recordedMetricsIDs } }
    var eventOrder: [String] { lock.withLock { order } }

    init(completed: XCTestExpectation, metrics: XCTestExpectation? = nil) {
        self.completed = completed
        self.metrics = metrics
    }
    func requestDidStart(_ event: CrmSdkNetworkRequest) {
        lock.withLock { recordedStarts.append(event); order.append("start") }
    }
    func requestDidComplete(_ event: CrmSdkNetworkResponse) {
        lock.withLock { recordedFinishes.append(event); order.append("complete") }
        completed.fulfill()
    }
    func requestDidCollectMetrics(_ metrics: URLSessionTaskMetrics, requestID: UUID) {
        lock.withLock { recordedMetricsIDs.append(requestID) }
        self.metrics?.fulfill()
    }
}

private final class MetricsSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let received: XCTestExpectation
    init(received: XCTestExpectation) { self.received = received }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        received.fulfill()
    }
}

private final class ReentrantNetworkObserver: CrmSdkNetworkObserver, @unchecked Sendable {
    let completed: XCTestExpectation
    init(completed: XCTestExpectation) { self.completed = completed }
    func requestDidStart(_ event: CrmSdkNetworkRequest) {
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60)
    }
    func requestDidComplete(_ event: CrmSdkNetworkResponse) { completed.fulfill() }
}

private final class ObserverURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "observer.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path.hasPrefix("/slow") == true { return }
        if request.url?.path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url?.path == "/bad" ? 400 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("response-body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
