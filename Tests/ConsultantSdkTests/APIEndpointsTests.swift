import XCTest
@testable import Core

final class APIEndpointsTests: XCTestCase {
    func testDefaultEndpoints() {
        let config = CrmSdkConfig(siteToken: "site")
        let endpoints = SessionConfig(siteToken: config.siteToken, baseURL: config.baseURL).endpoints
        XCTAssertEqual(config.baseURL, "https://c.retailcrm.tech")
        XCTAssertEqual(endpoints.clientAPIEndpointURL.absoluteString, "https://c.retailcrm.tech/api/client/v1")
        XCTAssertEqual(endpoints.clientWebSocketEndpointURL.absoluteString, "wss://c.retailcrm.tech/api/client/v1/ws")
    }

    func testCustomURLNormalization() {
        let cases: [(baseURL: String, http: String, socket: String)] = [
            ("https://consultant.example.com", "https://consultant.example.com/api/client/v1", "wss://consultant.example.com/api/client/v1/ws"),
            (" https://consultant.example.com///\n", "https://consultant.example.com/api/client/v1", "wss://consultant.example.com/api/client/v1/ws"),
            ("https://consultant.example.com/api/client/v1", "https://consultant.example.com/api/client/v1", "wss://consultant.example.com/api/client/v1/ws"),
            ("https://consultant.example.com/api/client/v1///", "https://consultant.example.com/api/client/v1", "wss://consultant.example.com/api/client/v1/ws"),
            ("http://localhost:8080/consultant/", "http://localhost:8080/consultant/api/client/v1", "ws://localhost:8080/consultant/api/client/v1/ws")
        ]
        for entry in cases {
            let endpoints = APIEndpoints(baseURL: entry.baseURL)
            XCTAssertEqual(endpoints.clientAPIEndpointURL.absoluteString, entry.http, entry.baseURL)
            XCTAssertEqual(endpoints.clientWebSocketEndpointURL.absoluteString, entry.socket, entry.baseURL)
        }
    }

}
