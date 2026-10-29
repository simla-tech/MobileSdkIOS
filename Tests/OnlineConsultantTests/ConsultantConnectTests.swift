import XCTest
@testable import OnlineConsultant

final class ConsultantConnectTests: XCTestCase {

    func testDecodesConnectResponseWithMessages() throws {
        let data = Data(
            """
            {
              "user": { "token": "user-token" },
              "session": { "id": 123 },
              "messages": [
                { "id": 7, "content": "Hello", "type": "text", "status": "sent", "from_me": false }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(ConsultantConnectResponse.self, from: data)

        XCTAssertEqual(response.user.token, "user-token")
        XCTAssertEqual(response.session.id?.value, "123")
        XCTAssertEqual(response.messages.map { $0.id?.value }, ["7"])
        XCTAssertEqual(response.messages.first?.content, "Hello")
        XCTAssertTrue(response.actions.isEmpty)
    }

    func testMissingOptionalConnectFieldsUseEmptyCollections() throws {
        let data = Data(
            """
            { "user": {}, "session": {} }
            """.utf8
        )

        let response = try JSONDecoder().decode(ConsultantConnectResponse.self, from: data)

        XCTAssertNil(response.config)
        XCTAssertNil(response.behaviour)
        XCTAssertTrue(response.messages.isEmpty)
        XCTAssertTrue(response.actions.isEmpty)
    }
}
