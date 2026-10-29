import XCTest
@testable import Core
@testable import OnlineConsultant

final class ConsultantWebSocketTests: XCTestCase {

    func testCustomBackendIsUsedForHTTPAndWebSocket() async throws {
        let network = FakeNetworkEngine(response: .init(statusCode: 200, body: Data("{}".utf8)))
        let socket = FakeWebSocketEngine()
        let client = OnlineConsultantClient(
            config: OnlineConsultantConfig(),
            sessionRuntime: SessionRuntime(config: SessionConfig(
                siteToken: "site-token", baseURL: "http://localhost:8080/proxy/api/client/v1/"
            )),
            networkEngine: network, webSocketEngine: socket
        )
        _ = try await client.loadMessages(session: "session", userToken: "user")
        XCTAssertEqual(network.lastGetRequest?.url.absoluteString,
                       "http://localhost:8080/proxy/api/client/v1/messages?limit=50&Offset=0")
        _ = client.subscribeRealtimeEvents(session: "session", userToken: "user")
        XCTAssertEqual(socket.lastRequest?.url.absoluteString,
                       "ws://localhost:8080/proxy/api/client/v1/ws?token=user&session=session&updated_at=undefined")
    }

    func testSubscribeRealtimeEventsBuildsURLAndYieldsDecodedEvents() async throws {
        let webSocketEngine = FakeWebSocketEngine(
            events: [
                .event(rawText: #"{"type":"message","data":{"id":"1","content":"Hello"}}"#)
            ]
        )
        let client = OnlineConsultantClient(
            config: OnlineConsultantConfig(),
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site-token")),
            networkEngine: FakeNetworkEngine(),
            webSocketEngine: webSocketEngine
        )

        var iterator = client.subscribeRealtimeEvents(
            session: "session-id",
            userToken: "user-token"
        ).makeAsyncIterator()
        let event = try await iterator.next()

        XCTAssertEqual(
            webSocketEngine.lastRequest?.url.absoluteString,
            "wss://c.retailcrm.tech/api/client/v1/ws?token=user-token&session=session-id&updated_at=undefined"
        )

        guard case .message(let message) = event else {
            return XCTFail("Expected message event")
        }

        XCTAssertEqual(message.id?.value, "1")
        XCTAssertEqual(message.content, "Hello")
    }

    func testSubscribeRealtimeEventsIncludesUpdatedAt() {
        let webSocketEngine = FakeWebSocketEngine()
        let client = OnlineConsultantClient(
            config: OnlineConsultantConfig(),
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site-token")),
            networkEngine: FakeNetworkEngine(),
            webSocketEngine: webSocketEngine
        )

        _ = client.subscribeRealtimeEvents(
            session: "session-id",
            userToken: "user-token",
            updatedAt: "2026-06-24T10:20:30.123456Z"
        )

        XCTAssertEqual(
            webSocketEngine.lastRequest?.url.absoluteString,
            "wss://c.retailcrm.tech/api/client/v1/ws?token=user-token&session=session-id&updated_at=2026-06-24T10:20:30.123456Z"
        )
    }

}

private final class FakeWebSocketEngine: ConsultantWebSocketEngine {

    private let events: [ConsultantWebSocketEvent]
    private(set) var lastRequest: ConsultantWebSocketRequest?

    init(events: [ConsultantWebSocketEvent] = []) {
        self.events = events
    }

    func open(_ request: ConsultantWebSocketRequest) -> AsyncThrowingStream<ConsultantWebSocketEvent, Error> {
        lastRequest = request

        return AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private final class FakeNetworkEngine: ConsultantNetworkEngine {

    private let response: ConsultantHTTPResponse
    private(set) var lastGetRequest: ConsultantHTTPRequest?

    init(response: ConsultantHTTPResponse = ConsultantHTTPResponse(statusCode: 200, body: Data())) {
        self.response = response
    }

    func getJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        lastGetRequest = request
        return response
    }

    func postJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(statusCode: 200, body: Data())
    }

    func postRaw(_ request: ConsultantRawHTTPRequest) async throws -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(statusCode: 200, body: Data())
    }
}
