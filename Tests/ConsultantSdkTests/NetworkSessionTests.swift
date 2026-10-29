import Foundation
import XCTest
@testable import Core

final class NetworkSessionTests: XCTestCase {
    func testCoreHTTPErrorMessages() {
        XCTAssertEqual(
            CoreError.errorMessages(from: Data(#"{"errors":["first","second"]}"#.utf8)),
            ["first", "second"]
        )
        XCTAssertEqual(
            CoreError.errorMessages(from: Data(#"{"error":"failed"}"#.utf8)),
            ["failed"]
        )
        XCTAssertEqual(
            CoreError.errorMessages(from: Data(#"{"errors":[],"message":"retry"}"#.utf8)),
            ["retry"]
        )
        XCTAssertEqual(CoreError.errorMessages(from: Data(#"{"errors":[]}"#.utf8)), [])
        XCTAssertEqual(CoreError.errorMessages(from: Data("  {invalid  ".utf8)), ["{invalid"])
        XCTAssertEqual(CoreError.errorMessages(from: Data()), [])
        XCTAssertTrue(CoreError.httpStatus(500, ["failed"]).localizedDescription.contains("failed"))
    }

    override func tearDown() {
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60)
        super.tearDown()
    }

    func testHTTPResponsesAndTransportErrors() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for (path, status) in [("success", 200), ("bad", 400), ("status", 503)] {
            let (data, response) = try await NetworkSession.data(
                for: URLRequest(url: URL(string: "https://network.test/\(path)")!), in: session
            )
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, status)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"result":"ok"}"#)
        }
        do {
            _ = try await NetworkSession.data(
                for: URLRequest(url: URL(string: "https://network.test/offline")!), in: session
            )
            XCTFail("Expected connection failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testTimeoutAndCancellation() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        NetworkSession.configure(requestTimeout: 0.05, resourceTimeout: 0.05)
        do {
            _ = try await NetworkSession.data(
                for: URLRequest(url: URL(string: "https://network.test/slow-timeout")!), in: session
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        NetworkSession.configure(requestTimeout: 30, resourceTimeout: 60)
        let task = Task {
            try await NetworkSession.data(
                for: URLRequest(url: URL(string: "https://network.test/slow-cancel")!), in: session
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkSessionURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class NetworkSessionURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "network.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path.hasPrefix("/slow") == true { return }
        if request.url?.path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status = request.url?.path == "/status" ? 503
            : (request.url?.path == "/bad" ? 400 : 200)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-Request-Id": "server-request-1"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"result":"ok"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
