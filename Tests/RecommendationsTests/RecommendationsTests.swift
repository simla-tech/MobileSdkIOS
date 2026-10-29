import Foundation
import XCTest
@testable import Core
@testable import Recommendations
@testable import Tracker

final class RecommendationsTests: XCTestCase {
    func testProductsUseCustomBackend() async throws {
        let service = makeService(baseURL: "https://consultant.example.com/api/client/v1/").service
        _ = try await service.getProducts(.init(mechanicCode: "mobile-home", blockCode: "home"))
        XCTAssertEqual(RecommendationsURLProtocol.requests().compactMap { $0.url?.absoluteString }, [
            "https://consultant.example.com/api/client/v1/connect",
            "https://consultant.example.com/api/client/v1/recommendations/products"
        ])
    }

    override func setUp() {
        super.setUp()
        RecommendationsURLProtocol.reset()
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    func testRequestNormalizesProductContext() throws {
        let request = ProductRecommendationsRequest(
            mechanicCode: "mobile", blockCode: " home ", productExternalID: " product-101 ", offerExternalID: " "
        )
        try request.validate()
        let body = try encodedBody(request)
        XCTAssertNil(body["mechanic_id"])
        XCTAssertEqual(body["mechanic_code"] as? String, "mobile")
        XCTAssertEqual(body["block_code"] as? String, "home")
        XCTAssertNil(body["system_customer_id"])
        XCTAssertNil(body["system_customer_external_id"])
        XCTAssertEqual(body["product_external_id"] as? String, "product-101")
        XCTAssertNil(body["offer_external_id"])
    }

    func testProductsFollowCustomerIdentityChangesAndLogout() async throws {
        let fixture = makeService(customerID: 37)
        let request = ProductRecommendationsRequest(mechanicCode: "personal", blockCode: "home")
        let identities: [CrmSdkCustomerIdentity?] = [
            CrmSdkCustomerIdentity(customerId: 81, siteCustomerId: "external-81", siteCode: "main"),
            CrmSdkCustomerIdentity(customerId: nil, siteCustomerId: "external-42", siteCode: "main"),
            nil
        ]
        for identity in identities {
            try await fixture.runtime.setCustomerIdentity(identity)
            _ = try await fixture.service.getProducts(request)
            let request = try XCTUnwrap(RecommendationsURLProtocol.requests().last { $0.url?.path == "/api/client/v1/recommendations/products" })
            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual((json["system_customer_id"] as? NSNumber)?.int64Value, identity?.customerId)
            XCTAssertEqual(
                json["system_customer_external_id"] as? String,
                identity?.customerId == nil ? identity?.siteCustomerId : nil
            )
            XCTAssertEqual(json["mechanic_code"] as? String, "personal")
            XCTAssertEqual(json["block_code"] as? String, "home")
        }
    }

    func testMechanicCodeFormatIsDelegatedToServer() throws {
        for code in ["mobile-home_1", "123", "Mobile", " mobile ", " ", "механика", "mobile/home", String(repeating: "a", count: 256)] {
            let request = ProductRecommendationsRequest(mechanicCode: code, blockCode: "home")
            try request.validate()
            let body = try encodedBody(request)
            XCTAssertEqual(body["mechanic_code"] as? String, code)
            XCTAssertNil(body["mechanic_id"])
        }
    }

    func testInvalidRequestStopsBeforeConnect() async throws {
        let service = makeService().service
        let invalidRequests = [
            ProductRecommendationsRequest(mechanicCode: "", blockCode: "home"),
            ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: " "),
            ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: "home", productID: 0),
            ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: "home", offerID: 0),
            ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: "home", productID: 1, offerID: 2)
        ]
        for request in invalidRequests {
            do {
                _ = try await service.getProducts(request)
                XCTFail("Invalid request was accepted")
            } catch let error as RecommendationsError {
                guard case .invalidRequest = error else { return XCTFail("Wrong error: \(error)") }
            }
        }
        XCTAssertTrue(RecommendationsURLProtocol.requests().isEmpty)
    }

    func testProductsUseConnectedSession() async throws {
        let service = makeService(customerID: 37).service
        let result = try await service.getProducts(
            ProductRecommendationsRequest(mechanicCode: "mobile-home", blockCode: " home ", productID: 101)
        )
        let requests = RecommendationsURLProtocol.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/client/v1/connect")
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.url?.path, "/api/client/v1/recommendations/products")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Site-Token"), "site-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-User-Token"), "user-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Session-Id"), "42")
        let body = try requestBody(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["mechanic_code"] as? String, "mobile-home")
        XCTAssertNil(json["mechanic_id"])
        XCTAssertEqual(json["system_customer_id"] as? Int, 37)
        XCTAssertEqual(json["product_id"] as? Int, 101)
        XCTAssertEqual(json["block_code"] as? String, "home")
        XCTAssertNil(json["strategy"])
        XCTAssertNil(json["limit"])

        XCTAssertEqual(result.executionID, 701)
        XCTAssertEqual(result.productIds, [101])
        XCTAssertEqual(result.products.first?.id, 1001)
        XCTAssertEqual(result.products.first?.productID, 101)
        XCTAssertEqual(result.products.first?.oldPrice, 0)
        XCTAssertEqual(result.products.first?.available, true)
    }

    func testEmptySelectionAndBackendErrors() async throws {
        RecommendationsURLProtocol.productBody = #"{"executionId":702,"personalized":false,"context":{"mechanicType":"popular"}}"#
        let service = makeService().service
        let empty = try await service.getProducts(ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: "home"))
        XCTAssertTrue(empty.productIds.isEmpty)
        XCTAssertTrue(empty.products.isEmpty)
        XCTAssertTrue(empty.context.required.isEmpty)

        for (status, code, message) in [(400, "Mobile", "Invalid product recommendation mechanic code."),
                                        (404, "mobile", "Mechanic was not found")] {
            RecommendationsURLProtocol.productStatus = status
            RecommendationsURLProtocol.productBody = String(decoding: try JSONSerialization.data(withJSONObject: ["errors": [message]]), as: UTF8.self)
            do {
                _ = try await service.getProducts(.init(mechanicCode: code, blockCode: "home"))
                XCTFail("Expected HTTP \(status)")
            } catch let error as RecommendationsError {
                XCTAssertEqual(error, .httpStatus(status, [message]), code)
            }
        }
    }

    func testUnreadableResponseIsTyped() async throws {
        RecommendationsURLProtocol.productBody = #"{"executionId":"invalid"}"#
        let service = makeService().service
        do {
            _ = try await service.getProducts(ProductRecommendationsRequest(mechanicCode: "mobile", blockCode: "home"))
            XCTFail("Expected response error")
        } catch let error as RecommendationsError {
            guard case .invalidResponse = error else { return XCTFail("Wrong error: \(error)") }
        }
    }

    func testImpressionAndClickUseTrackerQueue() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        fixture.tracker.sessionDidConnect(
            credentials: SessionCredentials(userToken: "user", sessionID: "42"),
            pageContext: ConnectPageContext(), user: ConnectUser(),
            response: ConnectResponse(
                user: ConnectedUser(token: "user"), session: ConnectedSession(),
                behaviour: ConnectBehaviour(tracker: true)
            ),
            customerIdentity: nil
        )
        _ = await fixture.tracker.flush()
        let recommendation = ProductRecommendations(
            executionID: UInt64.max, personalized: false,
            context: ProductRecommendationContext(mechanicType: "similar")
        )
        let impressionID = try await fixture.service.trackImpression(
            recommendation, screenURI: "app://products/101", title: "Product"
        )
        let clickID = try await fixture.service.trackClick(
            recommendation, productID: 101, position: 0,
            element: "recommendations#similar", leaving: true
        )
        let events = try fixture.storage.loadPendingEvents()
        XCTAssertEqual(events.map(\.id), [impressionID, clickID])
        XCTAssertEqual(events.map(\.type), ["page_view", "click"])
        XCTAssertEqual(events[0].pageURL, "app://products/101")
        XCTAssertEqual(events[1].pageURL, "app://products/101")
        XCTAssertEqual(events[0].data?["recommendation_execution_id"], .uint64(UInt64.max))
        XCTAssertEqual(events[1].data?["recommendation_execution_id"], .uint64(UInt64.max))
        XCTAssertEqual(events[1].data?["product_id"], .int(101))
        XCTAssertEqual(events[1].data?["recommendation_position"], .int(0))
        XCTAssertEqual(events[1].data?["el"], .string("recommendations#similar"))
        XCTAssertEqual(events[1].data?["leaving"], .bool(true))
        let json = String(decoding: try JSONEncoder().encode(events[1]), as: UTF8.self)
        XCTAssertTrue(json.contains("18446744073709551615"))
    }

    func testRecommendationsExposeSharedConsentAndEventAcceptance() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        fixture.tracker.sessionDidConnect(
            credentials: SessionCredentials(userToken: "user", sessionID: "42"),
            pageContext: ConnectPageContext(), user: ConnectUser(),
            response: ConnectResponse(
                user: ConnectedUser(token: "user"), session: ConnectedSession(),
                behaviour: ConnectBehaviour(tracker: true, consentForm: true)
            ),
            customerIdentity: nil
        )
        _ = await fixture.tracker.flush()
        XCTAssertTrue(fixture.tracker.requiresConsent)
        XCTAssertEqual(fixture.service.consentState, .unknown)
        let recommendation = ProductRecommendations(
            executionID: 701, personalized: false, context: .init(mechanicType: "similar")
        )
        do {
            _ = try await fixture.service.trackImpression(recommendation, screenURI: "app://home")
            XCTFail("Expected consent error")
        } catch let error as RecommendationsError {
            XCTAssertEqual(error, .consentRequired)
        }
        do {
            _ = try await fixture.service.trackClick(recommendation, productID: 0)
            XCTFail("Expected invalid product ID")
        } catch let error as RecommendationsError {
            guard case .invalidRequest = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
        guard case .success = fixture.service.setConsent(.granted) else {
            return XCTFail("Consent was not accepted")
        }
        XCTAssertEqual(fixture.service.consentState, .granted)
        await assertTrackingAcceptance(fixture.service, expectedError: nil)
        XCTAssertEqual(try fixture.storage.loadPendingEvents().count, 1)

        guard case .success = fixture.service.setConsent(.denied) else {
            return XCTFail("Consent denial was not accepted")
        }
        XCTAssertEqual(fixture.service.consentState, .denied)
        XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
        do {
            _ = try await fixture.service.trackImpression(recommendation, screenURI: "app://home")
            XCTFail("Denied tracking was accepted")
        } catch let error as RecommendationsError {
            XCTAssertEqual(error, .consentRequired)
        }
    }

    func testReadinessSharesPreparationAndPreservesQueue() async throws {
        RecommendationsURLProtocol.connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true,"consent_form":true}}"#
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        _ = try await fixture.runtime.start()
        let requiresForm = try await awaitReadiness(fixture.service)
        XCTAssertTrue(requiresForm)
        XCTAssertTrue(fixture.tracker.requiresConsent)
        await assertTrackingAcceptance(fixture.service, expectedError: .consentRequired)
        _ = await fixture.tracker.flush()
        try fixture.service.setConsent(.granted).get()
        let recommendation = ProductRecommendations(executionID: 701, personalized: false, context: .init(mechanicType: "similar"))
        let eventID = try await fixture.service.trackImpression(recommendation, screenURI: "app://home")
        let repeated = try await awaitReadiness(fixture.service)
        XCTAssertFalse(repeated)
        XCTAssertEqual(try fixture.storage.loadPendingEvents().map(\.id), [eventID])
        XCTAssertEqual(RecommendationsURLProtocol.requests().count, 1)

        try fixture.service.setConsent(.denied).get()
        RecommendationsURLProtocol.connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true,"consent_form":false}}"#
        try await fixture.runtime.setCustomerIdentity(.init(customerId: 123, siteCustomerId: nil, siteCode: nil))
        let reconnected = try await awaitReadiness(fixture.service)
        XCTAssertFalse(reconnected)
        XCTAssertFalse(fixture.tracker.requiresConsent)
        await assertTrackingAcceptance(fixture.service, expectedError: .trackingUnavailable)
        XCTAssertEqual(RecommendationsURLProtocol.requests().count, 2)
    }

    func testReadinessShowsFormOnlyForUnknownRequiredConsent() async throws {
        for requiresConsent in [false, true] {
            for (consent, expectedState): (RecommendationsConsentState, TrackerConsentState) in [(.unknown, .unknown), (.granted, .granted), (.denied, .denied)] {
                RecommendationsURLProtocol.connectBody = """
                {"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true,"consent_form":\(requiresConsent)}}
                """
                let fixture = try makeTrackingFixture()
                defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
                try fixture.service.setConsent(consent).get()
                _ = try await fixture.runtime.start()
                let requiresForm = try await awaitReadiness(fixture.service)
                XCTAssertEqual(requiresForm, requiresConsent && consent == .unknown, "\(requiresConsent), \(consent)")
                XCTAssertEqual(fixture.service.consentState, expectedState)
                if consent == .granted {
                    await assertTrackingAcceptance(fixture.service, expectedError: nil)
                }
            }
        }
    }

    func testReadinessWaitsForConnectionWithoutStartingIt() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        let premature = expectation(description: "no readiness before connection")
        premature.isInverted = true
        fixture.service.onReadyUpdate = { _, _ in premature.fulfill() }
        await fulfillment(of: [premature], timeout: 0.1)
        fixture.service.onReadyUpdate = nil
        XCTAssertTrue(RecommendationsURLProtocol.requests().isEmpty)
        XCTAssertFalse(fixture.storage.hasActiveScope)
        RecommendationsURLProtocol.connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true,"consent_form":true}}"#
        let ready = expectation(description: "automatically prepared")
        fixture.service.onReadyUpdate = { requiresForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(requiresForm)
            XCTAssertNil(error)
            ready.fulfill()
        }
        _ = try await fixture.runtime.start()
        await fulfillment(of: [ready], timeout: 3)
        fixture.service.onReadyUpdate = nil
        XCTAssertTrue(fixture.storage.hasActiveScope)
        XCTAssertEqual(RecommendationsURLProtocol.requests().count, 1)
    }

    func testReadinessReplaysFailedConnectionWithoutRetrying() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        RecommendationsURLProtocol.connectStatus = 503
        RecommendationsURLProtocol.connectBody = #"{"errors":["Unavailable"]}"#
        do { _ = try await fixture.runtime.start(); XCTFail("Expected connection failure") }
        catch { XCTAssertEqual(error as? CoreError, .httpStatus(503, ["Unavailable"])) }
        do { _ = try await awaitReadiness(fixture.service); XCTFail("Expected readiness failure") }
        catch { XCTAssertEqual(error as? TrackerError, .httpStatus(503, ["Unavailable"], retryAfter: nil)) }
        XCTAssertEqual(RecommendationsURLProtocol.requests().count, 1)
        XCTAssertFalse(fixture.storage.hasActiveScope)
    }

    func testReadinessHandlerIsSharedAndCanBeReplacedFromEitherModule() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        RecommendationsURLProtocol.connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true,"consent_form":true}}"#
        let replaced = expectation(description: "replaced handler is not called")
        replaced.isInverted = true
        fixture.tracker.onReadyUpdate = { _, _ in replaced.fulfill() }
        let ready = expectation(description: "recommendations receives shared result")
        fixture.service.onReadyUpdate = { requiresForm, error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(requiresForm)
            XCTAssertNil(error)
            ready.fulfill()
        }
        XCTAssertNotNil(fixture.tracker.onReadyUpdate)
        _ = try await fixture.runtime.start()
        await fulfillment(of: [ready], timeout: 3)
        await fulfillment(of: [replaced], timeout: 0.1)

        let changed = expectation(description: "tracker replaces recommendations handler")
        fixture.tracker.onReadyUpdate = { requiresForm, error in
            guard !requiresForm else { return }
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(error)
            changed.fulfill()
        }
        try fixture.service.setConsent(.granted).get()
        await fulfillment(of: [changed], timeout: 3)
        fixture.service.onReadyUpdate = nil
        XCTAssertNil(fixture.tracker.onReadyUpdate)
        XCTAssertNil(fixture.service.onReadyUpdate)

        fixture.service.onReadyUpdate = { _, _ in XCTFail("Cleared handler was called") }
        fixture.tracker.onReadyUpdate = nil
        XCTAssertNil(fixture.service.onReadyUpdate)
        try fixture.service.setConsent(.unknown).get()
        await MainActor.run { }
    }

    private func awaitReadiness(_ service: Recommendations) async throws -> Bool {
        let ready = expectation(description: "recommendations readiness")
        var result: Result<Bool, TrackerError>?
        service.onReadyUpdate = { requiresForm, error in
            XCTAssertTrue(Thread.isMainThread)
            result = error.map { .failure($0) } ?? .success(requiresForm)
            service.onReadyUpdate = nil
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 3)
        service.onReadyUpdate = nil
        return try XCTUnwrap(result).get()
    }

    func testCompletionReportsTypedErrorOnMainThread() async {
        let service = makeService().service
        let recommendation = ProductRecommendations(
            executionID: 701, personalized: false,
            context: ProductRecommendationContext(mechanicType: "similar")
        )
        let expectation = expectation(description: "completion")
        service.trackClick(recommendation, productID: 0) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .failure(.invalidRequest) = result else {
                XCTFail("Expected typed validation error")
                expectation.fulfill()
                return
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testRecommendationEventsReachCollectorAndReportDelivery() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        _ = try await fixture.runtime.start()
        _ = try await awaitReadiness(fixture.service)
        _ = await fixture.tracker.flush()
        let selection = try await fixture.service.getProducts(.init(mechanicCode: "mobile", blockCode: "test"))
        let impression = try await fixture.service.trackImpression(selection, screenURI: "app://recommendations")
        let click = try await fixture.service.trackClick(selection, productID: 101, position: 0)
        let delivered = expectation(description: "collector confirmed both events")
        fixture.tracker.onEventUpdate = { update in
            if case .delivered(let ids) = update, Set(ids) == Set([impression, click]) { delivered.fulfill() }
        }
        let flushed: Result<Void, TrackerError> = await withCheckedContinuation { continuation in
            fixture.tracker.flushAll { continuation.resume(returning: $0) }
        }
        try flushed.get()
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertTrue(try fixture.storage.loadPendingEvents().isEmpty)
        let request = try XCTUnwrap(RecommendationsURLProtocol.requests().last { $0.url?.path == "/api/client/v1/event" })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-User-Token"), "user-token")
        let body = try requestBody(request)
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["type"] as? String }, ["page_view", "click"])
        XCTAssertEqual((events[0]["data"] as? [String: Any])?["recommendation_execution_id"] as? Int, 701)
        XCTAssertEqual((events[1]["data"] as? [String: Any])?["product_id"] as? Int, 101)
        XCTAssertEqual((events[1]["data"] as? [String: Any])?["recommendation_position"] as? Int, 0)
    }

    func testCollectorRejectionAndRetryAreNotReportedAsDelivery() async throws {
        let fixture = try makeTrackingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        _ = try await fixture.runtime.start()
        _ = try await awaitReadiness(fixture.service)
        _ = await fixture.tracker.flush()
        let selection = ProductRecommendations(executionID: 701, personalized: false, context: .init(mechanicType: "similar"))
        let impression = try await fixture.service.trackImpression(selection, screenURI: "app://recommendations")
        let click = try await fixture.service.trackClick(selection, productID: 101)
        RecommendationsURLProtocol.eventBody = String(decoding: try JSONSerialization.data(withJSONObject: [
            impression: ["try_again": "try again later"], click: ["product_id": "invalid product"]
        ]), as: UTF8.self)
        let rejected = expectation(description: "rejected")
        let retry = expectation(description: "retry")
        fixture.tracker.onEventUpdate = { update in
            switch update {
            case .delivered: XCTFail("Failed events were reported as delivered")
            case .rejected(let id, let error):
                XCTAssertEqual(id, click)
                XCTAssertEqual(error, .eventRejected("product_id: invalid product"))
                rejected.fulfill()
            case .retryScheduled(let ids, _):
                XCTAssertEqual(ids, [impression])
                retry.fulfill()
            default: break
            }
        }
        let flushed: Result<Void, TrackerError> = await withCheckedContinuation { continuation in
            fixture.tracker.flushAll { continuation.resume(returning: $0) }
        }
        if case .success = flushed { XCTFail("Expected incomplete delivery") }
        await fulfillment(of: [rejected, retry], timeout: 2)
        XCTAssertEqual(try fixture.storage.loadPendingEvents().map(\.id), [impression])
    }

    func testRecommendationEventsAreAlsoSentByPeriodicFlush() async throws {
        let fixture = try makeTrackingFixture(flushInterval: 0.05)
        defer { try? FileManager.default.removeItem(at: fixture.databaseURL) }
        _ = try await fixture.runtime.start()
        _ = try await awaitReadiness(fixture.service)
        _ = await fixture.tracker.flush()
        let delivered = expectation(description: "automatic delivery")
        fixture.tracker.onEventUpdate = { update in
            if case .delivered = update { delivered.fulfill() }
        }
        let selection = ProductRecommendations(executionID: 701, personalized: false, context: .init(mechanicType: "similar"))
        _ = try await fixture.service.trackImpression(selection, screenURI: "app://recommendations")
        await fulfillment(of: [delivered], timeout: 3)
        try fixture.service.setConsent(.denied).get()
        XCTAssertTrue(RecommendationsURLProtocol.requests().contains { $0.url?.path == "/api/client/v1/event" })
    }

    private func assertTrackingAcceptance(
        _ service: Recommendations, expectedError: RecommendationsError?,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let recommendation = ProductRecommendations(
            executionID: 701, personalized: false, context: .init(mechanicType: "similar")
        )
        do {
            let id = try await service.trackImpression(recommendation, screenURI: "app://home")
            XCTAssertNil(expectedError, "Tracking should have been rejected", file: file, line: line)
            XCTAssertFalse(id.isEmpty, file: file, line: line)
        } catch let error as RecommendationsError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func encodedBody(_ request: ProductRecommendationsRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    private func makeService(
        customerID: Int64? = nil, baseURL: String = CrmSdkConfig.defaultBaseURL
    ) -> (service: Recommendations, runtime: SessionRuntime) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecommendationsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let identity = customerID.map {
            CrmSdkCustomerIdentity(customerId: $0, siteCustomerId: "external-37", siteCode: "main")
        }
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site-token", baseURL: baseURL),
            customerIdentity: identity,
            session: session,
            userTokenStorage: RecommendationTokenStorage()
        )
        let tracker = Tracker(config: TrackerConfig(flushInterval: 0), sessionRuntime: runtime, client: TrackerClient(sessionRuntime: runtime, session: session))
        return (Recommendations(sessionRuntime: runtime, tracker: tracker, session: session), runtime)
    }

    private func makeTrackingFixture(flushInterval: TimeInterval = 0) throws -> (
        service: Recommendations, tracker: Tracker,
        storage: SQLiteTrackerStorage, databaseURL: URL, runtime: SessionRuntime
    ) {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recommendations-\(UUID().uuidString).sqlite")
        let storage = try SQLiteTrackerStorage(databaseURL: databaseURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecommendationsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let runtime = SessionRuntime(
            config: SessionConfig(siteToken: "site-token"),
            session: session, userTokenStorage: RecommendationTokenStorage()
        )
        let tracker = Tracker(
            config: TrackerConfig(batchSize: 50, flushInterval: flushInterval),
            sessionRuntime: runtime, storage: storage, client: TrackerClient(sessionRuntime: runtime, session: session)
        )
        return (Recommendations(sessionRuntime: runtime, tracker: tracker, session: session), tracker, storage, databaseURL, runtime)
    }
}

private final class RecommendationTokenStorage: UserTokenStorage {
    private var token: String?

    func getUserToken(siteToken: String, customerIdentity: CrmSdkCustomerIdentity?) throws -> String? {
        token
    }

    func setUserToken(
        _ token: String?, siteToken: String, customerIdentity: CrmSdkCustomerIdentity?
    ) throws {
        self.token = token
    }
}

private final class RecommendationsURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedRequests: [URLRequest] = []
    static var connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true}}"#
    static var connectStatus = 200
    static var eventBody = "{}"
    static var productStatus = 200
    static var productBody = #"{"executionId":701,"personalized":false,"context":{"mechanicType":"similar","required":["product"]},"productIds":[101],"products":[{"id":1001,"productId":101,"name":"Offer","price":1500,"currency":"RUB"}]}"#

    static func reset() {
        lock.lock()
        capturedRequests = []
        connectBody = #"{"user":{"token":"user-token"},"session":{"id":42},"behaviour":{"tracker":true}}"#
        connectStatus = 200
        eventBody = "{}"
        productStatus = 200
        productBody = #"{"executionId":701,"personalized":false,"context":{"mechanicType":"similar","required":["product"]},"productIds":[101],"products":[{"id":1001,"productId":101,"name":"Offer","price":1500,"currency":"RUB"}]}"#
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        ["c.retailcrm.tech", "consultant.example.com"].contains(request.url?.host ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let connectBody = Self.connectBody
        let connectStatus = Self.connectStatus
        let status = Self.productStatus
        let body = Self.productBody
        let eventBody = Self.eventBody
        Self.lock.unlock()
        let isConnect = request.url?.path == "/api/client/v1/connect"
        let response = HTTPURLResponse(
            url: request.url!, statusCode: isConnect ? connectStatus : status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]
        )!
        let responseBody: String
        switch request.url?.path {
        case "/api/client/v1/connect": responseBody = connectBody
        case "/api/client/v1/event": responseBody = eventBody
        case "/api/client/v1/ts": responseBody = "{}"
        default: responseBody = body
        }
        var responseData = Data(responseBody.utf8)
        if isConnect, connectStatus == 200 {
            var json = try! JSONSerialization.jsonObject(with: responseData) as! [String: Any]
            json["ts"] = ISO8601DateFormatter().string(from: Date())
            responseData = try! JSONSerialization.data(withJSONObject: json)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
