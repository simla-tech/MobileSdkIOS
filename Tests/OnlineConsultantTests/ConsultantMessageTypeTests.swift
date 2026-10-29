import XCTest
@testable import OnlineConsultant

final class ConsultantMessageTypeTests: XCTestCase {

    func testMessageTypesMatchBackendJSON() throws {
        let cases: [(String, MessageType)] = [
            ("text", .text),
            ("system", .system),
            ("command", .command),
            ("order", .order),
            ("product", .product),
            ("file", .file),
            ("image", .image),
            ("auto_message", .unknown("auto_message")),
            ("contact_form", .contactForm),
            ("new_backend_type", .unknown("new_backend_type"))
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(MessageType(rawValue: raw), expected, raw)
            let data = try JSONEncoder().encode(ConsultantMessage(id: FlexibleID("message-1"), messageType: expected))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["type"] as? String, raw, raw)
        }
    }

    func testMessageStatusesMatchBackendJSON() throws {
        let cases: [(String, MessageStatus)] = [
            ("none", .none),
            ("new", .new),
            ("sent", .sent),
            ("seen", .seen),
            ("deleted", .deleted),
            ("failed", .failed),
            ("undefined", .undefined),
            ("sending", .sending),
            ("delivered", .delivered),
            ("received", .unknown("received"))
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(MessageStatus(rawValue: raw), expected, raw)
            let data = try JSONEncoder().encode(ConsultantMessage(id: FlexibleID("message-1"), status: expected))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["status"] as? String, raw, raw)
        }
    }

}
