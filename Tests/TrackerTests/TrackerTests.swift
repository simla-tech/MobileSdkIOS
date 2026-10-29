import Foundation
import XCTest
import SQLite3
@testable import Core
@testable import Tracker

final class TrackerTests: XCTestCase {
    func testCollectorAndServerTimeUseCustomBackend() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UtmTrackerProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        UtmTrackerProtocol.requests = []
        UtmTrackerProtocol.requestURLs = []
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site", baseURL: "http://localhost:8080/proxy/"),
            session: session, userTokenStorage: UtmTokenStorage()
        )
        _ = try await runtime.start()
        let client = TrackerClient(sessionRuntime: runtime, session: session)
        _ = try await client.fetchServerTime()
        // The fake collector fails the first event request, then accepts the retry.
        _ = try? await client.send(events: [TrackerEvent(type: "click")], expectedUserToken: "user")
        _ = try await client.send(events: [TrackerEvent(type: "click")], expectedUserToken: "user")
        XCTAssertEqual(UtmTrackerProtocol.requestURLs.map(\.absoluteString), [
            "http://localhost:8080/proxy/api/client/v1/connect",
            "http://localhost:8080/proxy/api/client/v1/ts?user=user&session=1",
            "http://localhost:8080/proxy/api/client/v1/event?user=user&session=1",
            "http://localhost:8080/proxy/api/client/v1/event?user=user&session=1"
        ])
    }

    func testSendingPayloadMatchesRequestBodyForFailedAndSuccessfulAttempts() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UtmTrackerProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        UtmTrackerProtocol.requests = []
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "payload-test"), session: session, userTokenStorage: UtmTokenStorage()
        )
        let _: ConnectResponse = try await runtime.connect(responseType: ConnectResponse.self)
        let client = TrackerClient(sessionRuntime: runtime, session: session)
        let events = [
            TrackerEvent(id: "first", type: "click", pageTitle: "Товар 🌍\n\"/", systemCustomerID: 42),
            TrackerEvent(id: "second", type: "order", utm: CrmUtmAttribution(campaign: "push"))
        ]
        var payloads: [String] = []
        for attempt in 0..<2 {
            do {
                _ = try await client.send(events: events, expectedUserToken: "user") { payload in
                    // The callback must precede the corresponding network attempt.
                    XCTAssertEqual(UtmTrackerProtocol.requests.count, attempt)
                    payloads.append(payload)
                }
                XCTAssertEqual(attempt, 1)
            } catch {
                XCTAssertEqual(attempt, 0)
                XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            }
        }
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(UtmTrackerProtocol.requests.count, 2)
        XCTAssertEqual(payloads.map { Data($0.utf8) }, UtmTrackerProtocol.requests)
        for payload in payloads {
            XCTAssertEqual(try JSONDecoder().decode([TrackerEvent].self, from: Data(payload.utf8)), events)
        }
    }

    func testSendingIsNotReportedWithoutConnection() async throws {
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "payload-test"))
        let client = TrackerClient(sessionRuntime: runtime)
        do {
            _ = try await client.send(events: [TrackerEvent(type: "click")], expectedUserToken: "user") { _ in
                XCTFail("No request can be sent without connection credentials")
            }
            XCTFail("Expected missingConnection")
        } catch {
            XCTAssertEqual(error as? TrackerError, .missingConnection)
        }
    }

    func testRestoredOrderIsSentWithOriginalUtmAfterNetworkFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UtmTrackerProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        UtmTrackerProtocol.requests = []
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "utm-test"), session: session, userTokenStorage: UtmTokenStorage())
        let _: ConnectResponse = try await runtime.connect(responseType: ConnectResponse.self)
        let client = TrackerClient(sessionRuntime: runtime, session: session)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("utm-retry-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let order = TrackerEvent(type: "order", utm: CrmUtmAttribution(campaign: "original"))
        do {
            let storage = try SQLiteTrackerStorage(databaseURL: url)
            try storage.activateScope(siteToken: "utm-test", userToken: "user")
            try storage.appendPendingEvent(order, dropping: [])
            do {
                _ = try await client.send(events: [order], expectedUserToken: "user")
                XCTFail("Expected network failure")
            } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        }
        let restoredStorage = try SQLiteTrackerStorage(databaseURL: url)
        try restoredStorage.activateScope(siteToken: "utm-test", userToken: "user")
        let events = try restoredStorage.loadPendingEvents()
        _ = try await client.send(events: events, expectedUserToken: "user")
        XCTAssertEqual(UtmTrackerProtocol.requests.count, 2)
        for body in UtmTrackerProtocol.requests {
            XCTAssertEqual(try JSONDecoder().decode([TrackerEvent].self, from: body), [order])
        }
    }

    func testOrderUtmSurvivesStartupRetryAndStorageReopening() async throws {
        let fixture = try makeStartupFixture()
        defer {
            CrmUtmAttributionStorage.shared.clear()
            try? FileManager.default.removeItem(at: fixture.url)
        }
        let original = try XCTUnwrap(CrmUtmAttribution(source: "push", campaign: "first", term: "shoes"))
        CrmUtmAttributionStorage.shared.save(original)
        let orderID = try await fixture.tracker.trackOrder(identifier: .externalID("order-utm"))
        CrmUtmAttributionStorage.shared.save(try XCTUnwrap(CrmUtmAttribution(campaign: "second")))
        let clickID = try await fixture.tracker.trackClick(element: "buy")
        await connectStartupFixture(fixture.tracker)
        let events = try fixture.storage.loadPendingEvents()
        let order = try XCTUnwrap(events.first { $0.id == orderID })
        XCTAssertEqual(order.utm, original)
        XCTAssertEqual(order.systemCustomerID, 42)
        XCTAssertNil(events.first { $0.id == clickID }?.utm)
        // A failed flush must leave the persisted event intact.
        _ = await fixture.tracker.flush()
        CrmUtmAttributionStorage.shared.clear()
        let reopened = try SQLiteTrackerStorage(databaseURL: fixture.url)
        try reopened.activateScope(siteToken: "site", userToken: "user")
        let restored = try XCTUnwrap(reopened.loadPendingEvents().first { $0.id == orderID })
        XCTAssertEqual(restored, order)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        let utm = try XCTUnwrap(json["utm"] as? [String: String])
        XCTAssertEqual(utm, ["utm_source": "push", "utm_campaign": "first", "utm_keyword": "shoes"])
        XCTAssertNil(utm["utm_term"])
        let noUtmID = try await fixture.tracker.trackOrder(identifier: .externalID("no-utm"))
        XCTAssertNil(try reopened.loadPendingEvents().first { $0.id == noUtmID }?.utm)
    }

    func testOrderEventMatchesBackendJSONContract() throws {
        let event = TrackerEvent(
            id: "event-1", type: "order",
            data: try TrackerEventDataFactory.order(
                identifier: .externalID("order-42"), cartID: "cart-7",
                items: [TrackerCartItem(offer: .xmlID("offer-3"), price: 12.5, quantity: 2)],
                deliveryPrice: 5, total: 30
            ),
            pageURL: "app://shop/cart", timestamp: "2026-10-14T10:00:00Z",
            systemCustomerID: 42
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let items = try XCTUnwrap(data["items"] as? [[String: Any]])
        XCTAssertEqual(json["type"] as? String, "order")
        XCTAssertEqual(json["page_url"] as? String, "app://shop/cart")
        XCTAssertEqual(json["system_customer_id"] as? Int, 42)
        XCTAssertEqual(data["order_external_id"] as? String, "order-42")
        XCTAssertEqual(data["cart_id"] as? String, "cart-7")
        XCTAssertEqual(items.first?["xml_id"] as? String, "offer-3")
        XCTAssertEqual(items.first?["quantity"] as? Int, 2)
        XCTAssertNil(json["system_customer_external_id"])
    }

    func testOrderIdentifiersSurviveQueueStorageAndJSONEncoding() async throws {
        let fixture = try makeStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let cases: [(TrackerOrderIdentifier, String, TrackerEventDataValue)] = [
            (.systemID(1), "order_id", .int(1)),
            (.systemID(Int64(Int32.max)), "order_id", .int(Int(Int32.max))),
            (.externalID("order-42"), "order_external_id", .string("order-42")),
            (.number("R-42"), "order_number", .string("R-42"))
        ]
        var eventIDs: [String] = []
        for (identifier, _, _) in cases {
            eventIDs.append(try await fixture.tracker.trackOrder(identifier: identifier))
        }
        await connectStartupFixture(fixture.tracker)
        let reopened = try SQLiteTrackerStorage(databaseURL: fixture.url)
        try reopened.activateScope(siteToken: "site", userToken: "user")
        let events = try reopened.loadPendingEvents()
        for (index, entry) in cases.enumerated() {
            let (_, key, value) = entry
            let event = try XCTUnwrap(events.first { $0.id == eventIDs[index] })
            XCTAssertEqual(event.type, "order")
            XCTAssertEqual(event.data, [key: value])
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
            let data = try XCTUnwrap(json["data"] as? [String: Any])
            if case let .int(id) = value {
                XCTAssertEqual(data[key] as? Int64, Int64(id))
                XCTAssertFalse(data[key] is String)
            } else if case let .string(id) = value {
                XCTAssertEqual(data[key] as? String, id)
            }
            for otherKey in ["order_id", "order_external_id", "order_number"] where otherKey != key {
                XCTAssertNil(data[otherKey])
            }
        }
    }

    func testOrderSystemIDRejectsValuesOutsideCRMRange() async throws {
        let fixture = try makeStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        for id: Int64 in [Int64.min, -1, 0, Int64(Int32.max) + 1, Int64.max] {
            do {
                _ = try await fixture.tracker.trackOrder(identifier: .systemID(id))
                XCTFail("Expected invalidEvent for order ID \(id)")
            } catch {
                guard case .invalidEvent = error as? TrackerError else {
                    return XCTFail("Expected invalidEvent, got \(error)")
                }
            }
            let result = await withCheckedContinuation { continuation in
                fixture.tracker.trackOrder(identifier: .systemID(id)) {
                    continuation.resume(returning: $0)
                }
            }
            guard case .failure(.invalidEvent) = result else {
                return XCTFail("Expected invalidEvent for order ID \(id)")
            }
        }
        await connectStartupFixture(fixture.tracker)
        XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
    }

    func testBackendResponseSeparatesRetryAndRejection() throws {
        let response = try JSONDecoder().decode(
            TrackerStoreEventsResponse.self,
            from: Data("{\"one\":{\"page_url\":\"try again later\"},\"two\":{\"data\":\"invalid offer\"}}".utf8)
        )
        let failures = response.failures(attemptedEventIDs: ["one", "two", "three"])
        XCTAssertEqual(failures.retryableIDs, ["one"])
        XCTAssertEqual(failures.rejectedReasons, ["two": "data: invalid offer"])
        XCTAssertThrowsError(try JSONDecoder().decode(
            TrackerStoreEventsResponse.self,
            from: Data("{\"unexpected\":[1,2]}".utf8)
        ))
    }

    func testTrackerRequiresConsentAndClearsQueueOnDenial() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = try SQLiteTrackerStorage(databaseURL: url)
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "site"))
        let tracker = Tracker(
            config: TrackerConfig(batchSize: 50, flushInterval: 0),
            sessionRuntime: runtime, storage: storage
        )
        guard case .success = tracker.setConsent(.granted) else {
            return XCTFail("Consent could not be granted.")
        }
        tracker.sessionDidConnect(
            credentials: SessionCredentials(userToken: "user", sessionID: "session"),
            pageContext: ConnectPageContext(), user: ConnectUser(),
            response: ConnectResponse(
                user: ConnectedUser(token: "user"),
                session: ConnectedSession(),
                behaviour: ConnectBehaviour(tracker: true, consentForm: true)
            ),
            customerIdentity: nil
        )
        _ = await tracker.flush()
        let queuedID = try await tracker.trackClick(element: "buy")
        XCTAssertFalse(queuedID.isEmpty)
        XCTAssertEqual(tracker.pendingEventCount, 1)
        XCTAssertEqual(try storage.loadPendingEvents().count, 1)
        guard case .success = tracker.setConsent(.denied) else {
            return XCTFail("Consent could not be denied.")
        }
        XCTAssertEqual(tracker.pendingEventCount, 0)
        XCTAssertTrue(try storage.loadPendingEvents().isEmpty)
        let deniedResult = await withCheckedContinuation { continuation in
            tracker.trackClick(element: "buy") { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(deniedResult, .failure(.consentRequired))
    }

    func testInvalidPublicEventReturnsTrackerError() async {
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "site"))
        let tracker = Tracker(config: TrackerConfig(), sessionRuntime: runtime)
        let pageResult = await withCheckedContinuation { continuation in
            tracker.trackPageView(screenURI: "relative/path") { continuation.resume(returning: $0) }
        }
        guard case let .failure(.invalidEvent(uriReason)) = pageResult else {
            return XCTFail("Expected a TrackerError for a relative URI.")
        }
        XCTAssertTrue(uriReason.contains("screenURI"))
        let cartResult = await withCheckedContinuation { continuation in
            tracker.trackCart(
                cartID: "cart",
                items: [TrackerCartItem(offer: .systemID(1), price: -.infinity, quantity: 1)]
            ) { continuation.resume(returning: $0) }
        }
        guard case let .failure(.invalidEvent(priceReason)) = cartResult else {
            return XCTFail("Expected a TrackerError for an infinite price.")
        }
        XCTAssertTrue(priceReason.contains("price"))

        do {
            _ = try await tracker.trackPageView(screenURI: "relative/path")
            XCTFail("Expected an invalid URI error from the async method.")
        } catch let error as TrackerError {
            guard case .invalidEvent = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAsyncFlushAllReportsMissingConnection() async {
        let runtime = SessionRuntime(config: SessionConfig(siteToken: "site"))
        let tracker = Tracker(config: TrackerConfig(), sessionRuntime: runtime)

        do {
            try await tracker.flushAll()
            XCTFail("Expected a missing connection error.")
        } catch let error as TrackerError {
            XCTAssertEqual(error, .missingConnection)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartupBufferPreservesOrderContextAndEventIDs() async throws {
        let fixture = try makeStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let first = try await fixture.tracker.trackPageView(screenURI: "app://shop", title: "Shop")
        let click = try await fixture.tracker.trackClick(element: "product")
        let second = try await fixture.tracker.trackPageView(screenURI: "app://product", title: "Product")
        let form = try await fixture.tracker.trackFormStart(formSelector: "checkout")
        let latestStartupTimestamp = TrackerEventTimestamp.make()
        await connectStartupFixture(fixture.tracker)
        let later = try await fixture.tracker.trackClick(element: "buy")
        let events = try fixture.storage.loadPendingEvents()
        XCTAssertEqual(events.map(\.id), [first, click, second, form, later])
        XCTAssertEqual(events.map(\.pageURL), ["app://shop", "app://shop", "app://product", "app://product", "app://product"])
        XCTAssertEqual(events[2].referrerURL, "app://shop")
        XCTAssertEqual(events[3].referrerURL, "app://shop")
        XCTAssertTrue(events.prefix(4).allSatisfy { $0.timestamp <= latestStartupTimestamp })
        XCTAssertTrue(events.allSatisfy { $0.systemCustomerID == 42 })
    }

    func testStartupConsentAndAvailability() async throws {
        for consent: TrackerConsentState in [.unknown, .granted, .denied] {
            for requiresConsent in [false, true] {
                for available in [false, true] {
                    let fixture = try makeStartupFixture()
                    defer { try? FileManager.default.removeItem(at: fixture.url) }
                    try fixture.tracker.setConsent(consent).get()
                    let result = await withCheckedContinuation { continuation in
                        fixture.tracker.trackClick(element: "early") { continuation.resume(returning: $0) }
                    }
                    if consent == .denied {
                        XCTAssertEqual(result, .failure(.consentRequired))
                    } else {
                        _ = try result.get()
                    }
                    await connectStartupFixture(fixture.tracker, requiresConsent: requiresConsent, available: available)
                    let shouldRetain = available && consent != .denied && (!requiresConsent || consent == .granted)
                    XCTAssertEqual(try fixture.storage.loadPendingEvents().count, shouldRetain ? 1 : 0)
                    // Later consent must not resurrect discarded startup history.
                    try fixture.tracker.setConsent(.granted).get()
                    XCTAssertEqual(try fixture.storage.loadPendingEvents().count, shouldRetain ? 1 : 0)
                }
            }
        }
    }

    func testStartupDenialAndDisconnectClearBufferedEvents() async throws {
        for disconnect in [false, true] {
            let fixture = try makeStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.url) }
            let id = try await fixture.tracker.trackPageView(screenURI: "app://old-user")
            let dropped = expectation(description: "buffer cleared")
            fixture.tracker.onEventUpdate = { update in
                if case .dropped(let ids, _) = update, ids.contains(id) { dropped.fulfill() }
            }
            if disconnect {
                fixture.tracker.sessionDidDisconnect()
            } else {
                try fixture.tracker.setConsent(.denied).get()
                try fixture.tracker.setConsent(.granted).get()
            }
            await fulfillment(of: [dropped], timeout: 2)
            await connectStartupFixture(fixture.tracker)
            XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
            _ = try await fixture.tracker.trackClick(element: "new-user")
            XCTAssertNil(try fixture.storage.loadPendingEvents().first?.pageURL)
        }
    }

    func testStartupBufferDropsOldestEventsAtCapacity() async throws {
        let fixture = try makeStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        var ids: [String] = []
        for index in 0..<1_001 {
            ids.append(try await fixture.tracker.trackClick(element: "item-\(index)"))
        }
        await connectStartupFixture(fixture.tracker)
        XCTAssertEqual(try fixture.storage.loadPendingEvents().map(\.id), Array(ids.suffix(1_000)))
    }

    func testStartupStorageFailureRetainsBufferAndUserChangeDropsIt() async throws {
        for changeUser in [false, true] {
            let fixture = try makeStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.url) }
            var database: OpaquePointer?
            XCTAssertEqual(sqlite3_open(fixture.url.path, &database), SQLITE_OK)
            defer { sqlite3_close(database) }
            XCTAssertEqual(sqlite3_exec(database, """
                CREATE TRIGGER fail_startup BEFORE INSERT ON tracker_events
                BEGIN SELECT RAISE(FAIL, 'test write failure'); END;
                """, nil, nil, nil), SQLITE_OK)
            let id = try await fixture.tracker.trackClick(element: "startup")
            await connectStartupFixture(fixture.tracker)
            let flushResult = await fixture.tracker.flush()
            guard case .failure(.storage) = flushResult else {
                return XCTFail("Expected a storage failure, got \(flushResult)")
            }
            XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
            XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER fail_startup", nil, nil, nil), SQLITE_OK)
            await connectStartupFixture(fixture.tracker, userToken: changeUser ? "other-user" : "user")
            XCTAssertEqual(try fixture.storage.loadPendingEvents().map(\.id), changeUser ? [] : [id])
        }
    }

    func testDisconnectClearsPersistedEventsBeforeReconnect() async throws {
        let fixture = try makeStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        await connectStartupFixture(fixture.tracker)
        _ = try await fixture.tracker.trackClick(element: "old-user")
        try fixture.storage.moveToOversized(TrackerEvent(id: "large", type: "click"))
        fixture.tracker.sessionDidDisconnect()
        // No successful reconnect is required for deleting the previous customer's data.
        let reopened = try SQLiteTrackerStorage(databaseURL: fixture.url)
        try reopened.activateScope(siteToken: "site", userToken: "user")
        XCTAssertTrue(try reopened.loadPendingEvents().isEmpty)
        XCTAssertTrue(try reopened.loadOversizedEventIDs().isEmpty)
        await connectStartupFixture(fixture.tracker)
        XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
    }

    private func makeStartupFixture() throws -> (tracker: Tracker, storage: SQLiteTrackerStorage, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("startup-\(UUID().uuidString).sqlite")
        let storage = try SQLiteTrackerStorage(databaseURL: url)
        let tracker = Tracker(
            config: TrackerConfig(batchSize: 50, flushInterval: 0),
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site")), storage: storage
        )
        return (tracker, storage, url)
    }

    private func connectStartupFixture(
        _ tracker: Tracker, requiresConsent: Bool = false, available: Bool = true, userToken: String = "user"
    ) async {
        tracker.sessionDidConnect(
            credentials: SessionCredentials(userToken: userToken, sessionID: "session"),
            pageContext: ConnectPageContext(), user: ConnectUser(),
            response: ConnectResponse(
                user: ConnectedUser(token: userToken), session: ConnectedSession(),
                behaviour: ConnectBehaviour(tracker: available, consentForm: requiresConsent)
            ),
            customerIdentity: CrmSdkCustomerIdentity(customerId: 42, siteCustomerId: nil, siteCode: nil)
        )
        _ = await tracker.flush()
    }

    func testStringErrorsHaveLocalizedDescriptions() {
        let errors: [TrackerError] = [
            .invalidEvent("detail"), .storage("detail"),
            .requestEncodingFailed("detail"), .requestFailed("detail"),
            .invalidResponse("detail"), .eventRejected("detail"),
            .httpStatus(400, ["detail"], retryAfter: nil)
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("detail"))
            XCTAssertNotEqual(description, "detail")
            XCTAssertFalse(description.contains("tracker.error."))
        }
    }
}

private final class UtmTrackerProtocol: URLProtocol {
    static var requests: [Data] = []
    static var requestURLs: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURLs.append(request.url!)
        let isEvent = request.url!.lastPathComponent == "event"
        if isEvent {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
            }
            Self.requests.append(body)
            if Self.requests.count == 1 {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
        }
        let data = Data((isEvent ? "{}" : #"{"user":{"token":"user"},"session":{"id":1},"behaviour":{"tracker":true}}"#).utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class UtmTokenStorage: UserTokenStorage {
    func getUserToken(siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws -> String? { nil }
    func setUserToken(_ token: String?, siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws {}
}
