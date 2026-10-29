import Foundation
import XCTest
@testable import Core

final class ConsultantSdkTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ConnectURLProtocol.reset()
    }

    func testSessionRuntimeConnectsAndStoresCredentials() async throws {
        ConnectURLProtocol.reset(responseBody: """
            {"user":{"token":"user-token"},"session":{"id":"session-id"}}
            """)
        let storage = MemoryUserTokenStorage()
        let runtime = makeRuntime(storage: storage)

        let credentials = try await runtime.start()
        let request = try XCTUnwrap(ConnectURLProtocol.capturedRequest())
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )

        XCTAssertEqual(credentials.userToken, "user-token")
        XCTAssertEqual(credentials.sessionID, "session-id")
        XCTAssertEqual(storage.token, "user-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Site-Token"), "site-token")
        XCTAssertEqual(body["page_title"] as? String, "Sample Shop")
    }

    func testSessionRuntimeRejectsMissingCredentials() async {
        ConnectURLProtocol.reset(responseBody: "{\"user\":{},\"session\":{}}")
        let runtime = makeRuntime(storage: MemoryUserTokenStorage())

        do {
            _ = try await runtime.start()
            XCTFail("Expected missing connection credentials")
        } catch {
            XCTAssertEqual(error as? CoreError, .missingConnectionCredentials)
        }
    }

    func testSessionRuntimeConnectsToCustomBackend() async throws {
        ConnectURLProtocol.reset(responseBody: """
            {"user":{"token":"user-token"},"session":{"id":"session-id"}}
            """)
        let runtime = makeRuntime(storage: MemoryUserTokenStorage(), baseURL: "http://localhost:8080/proxy/")
        _ = try await runtime.start()
        XCTAssertEqual(ConnectURLProtocol.capturedRequest()?.url?.absoluteString,
                       "http://localhost:8080/proxy/api/client/v1/connect")
    }

    private func makeRuntime(
        storage: MemoryUserTokenStorage, baseURL: String = CrmSdkConfig.defaultBaseURL
    ) -> SessionRuntime {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectURLProtocol.self]
        return SessionRuntime(
            config: SessionConfig(siteToken: "site-token", baseURL: baseURL),
            pageContext: ConnectPageContext(title: "Sample Shop"),
            session: URLSession(configuration: configuration),
            userTokenStorage: storage
        )
    }
}

private final class MemoryUserTokenStorage: UserTokenStorage {
    private(set) var token: String?

    func getUserToken(
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws -> String? {
        token
    }

    func setUserToken(
        _ token: String?,
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws {
        self.token = token
    }
}

private final class ConnectURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseBody = "{}"
    private static var requestSnapshot: URLRequest?

    static func reset(responseBody: String = "{}") {
        lock.lock()
        defer { lock.unlock() }
        self.responseBody = responseBody
        requestSnapshot = nil
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requestSnapshot
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/api/client/v1/connect") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var capturedRequest = request
        capturedRequest.httpBody = request.httpBody ?? data(from: request.httpBodyStream)
        let body: String
        Self.lock.lock()
        Self.requestSnapshot = capturedRequest
        body = Self.responseBody
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func data(from stream: InputStream?) -> Data? {
    guard let stream else { return nil }
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}
