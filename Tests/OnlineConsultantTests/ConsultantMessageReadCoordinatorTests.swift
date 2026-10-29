import XCTest
@testable import Core
@testable import OnlineConsultant

@MainActor
final class ConsultantMessageReadCoordinatorTests: XCTestCase {

    func testScheduleCoalescesPendingMessageIDsAndSendsOnlyGreatestID() async throws {
        let networkEngine = MessageReadNetworkEngine()
        let coordinator = makeCoordinator(networkEngine: networkEngine)
        var errors: [Error] = []

        coordinator.schedule(
            messageID: "10",
            session: "session-id",
            userToken: "user-token",
            handleError: { errors.append($0) }
        )
        coordinator.schedule(
            messageID: "12",
            session: "session-id",
            userToken: "user-token",
            handleError: { errors.append($0) }
        )
        coordinator.schedule(
            messageID: "11",
            session: "session-id",
            userToken: "user-token",
            handleError: { errors.append($0) }
        )

        try await waitUntil { networkEngine.postRequests.count == 1 }

        let request = try XCTUnwrap(networkEngine.postRequests.first)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://c.retailcrm.tech/api/client/v1/messages/12/read"
        )
        XCTAssertEqual(request.headers["X-Site-Token"], "site-token")
        XCTAssertEqual(request.headers["X-User-Token"], "user-token")
        XCTAssertEqual(request.headers["X-Session-Id"], "session-id")
        XCTAssertTrue(errors.isEmpty)
    }

    func testScheduleIgnoresNonNumericAndAlreadySubmittedMessageIDs() async throws {
        let networkEngine = MessageReadNetworkEngine()
        let coordinator = makeCoordinator(networkEngine: networkEngine)

        coordinator.schedule(
            messageID: "5",
            session: "session-id",
            userToken: "user-token",
            handleError: { _ in }
        )

        try await waitUntil { networkEngine.postRequests.count == 1 }

        coordinator.schedule(
            messageID: "4",
            session: "session-id",
            userToken: "user-token",
            handleError: { _ in }
        )
        coordinator.schedule(
            messageID: "_local_1",
            session: "session-id",
            userToken: "user-token",
            handleError: { _ in }
        )
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(networkEngine.postRequests.count, 1)
    }

    func testResetCancelsPendingReadRequest() async throws {
        let networkEngine = MessageReadNetworkEngine()
        let coordinator = makeCoordinator(networkEngine: networkEngine)

        coordinator.schedule(
            messageID: "7",
            session: "session-id",
            userToken: "user-token",
            handleError: { _ in }
        )
        coordinator.reset()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(networkEngine.postRequests.isEmpty)
    }
}

private extension ConsultantMessageReadCoordinatorTests {

    func makeCoordinator(
        networkEngine: MessageReadNetworkEngine
    ) -> MessageReadCoordinator {
        MessageReadCoordinator(
            client: OnlineConsultantClient(
                config: OnlineConsultantConfig(),
                sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site-token")),
                networkEngine: networkEngine
            ),
            debounceNanoseconds: 1_000_000
        )
    }

    func waitUntil(
        _ condition: @escaping () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for condition")
    }
}

private final class MessageReadNetworkEngine: ConsultantNetworkEngine {

    private(set) var postRequests: [ConsultantHTTPRequest] = []

    func getJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(statusCode: 200, body: Data())
    }

    func postJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        postRequests.append(request)
        return ConsultantHTTPResponse(statusCode: 200, body: Data(#"{}"#.utf8))
    }

    func postRaw(_ request: ConsultantRawHTTPRequest) async throws -> ConsultantHTTPResponse {
        ConsultantHTTPResponse(statusCode: 200, body: Data())
    }
}
