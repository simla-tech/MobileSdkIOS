import Foundation
import XCTest
import SQLiteStorage
@testable import PushService

final class PushRegistrationStorageTests: XCTestCase {
    func testRegistrationListsAndFingerprintSurviveReopeningAndStayIsolatedBySite() throws {
        let url = temporaryURL()
        do {
            let storage = PushRegistrationStorage(databaseURL: url)
            XCTAssertEqual(try storage.setDesiredCategories(["orders"], site: "first"), [])
            try storage.setSystemCategories(["orders"], site: "first")
            try storage.confirm(fingerprint: "accepted", categories: ["orders"], site: "first")
            try storage.setDesiredCategories(["news"], site: "second")
        }
        let reopened = PushRegistrationStorage(databaseURL: url)
        XCTAssertEqual(try reopened.load(site: "first"), .init(
            fingerprint: "accepted", desiredCategories: ["orders"], confirmedCategories: ["orders"], systemCategories: ["orders"]
        ))
        XCTAssertEqual(try reopened.load(site: "second"), .init(desiredCategories: ["news"]))
        XCTAssertEqual(try reopened.load(site: "missing"), .init())
        XCTAssertEqual(try reopened.setDesiredCategories([], site: "first"), ["orders"])
        try reopened.invalidateFingerprint(site: "first")
        let state = try reopened.load(site: "first")
        XCTAssertNil(state.fingerprint)
        XCTAssertEqual(state.desiredCategories, [])
        XCTAssertEqual(state.confirmedCategories, ["orders"])
        XCTAssertEqual(state.systemCategories, ["orders"])
        try reopened.confirm(fingerprint: "unsubscribed", categories: [], site: "first")
        XCTAssertEqual(try reopened.load(site: "first").confirmedCategories, [])
    }

    func testFailedConfirmationDoesNotPartiallyChangeFingerprintOrCategories() throws {
        let url = temporaryURL()
        let storage = PushRegistrationStorage(databaseURL: url)
        try storage.confirm(fingerprint: "old", categories: ["orders"], site: "site")
        let database = try SQLiteDatabase(url: url)
        try database.withConnection { try $0.execute("""
            CREATE TRIGGER reject_confirmation BEFORE UPDATE ON push_registration
            BEGIN SELECT RAISE(FAIL, 'test failure'); END;
            """) }
        XCTAssertThrowsError(try storage.confirm(fingerprint: "new", categories: ["news"], site: "site"))
        XCTAssertEqual(try storage.load(site: "site").fingerprint, "old")
        XCTAssertEqual(try storage.load(site: "site").confirmedCategories, ["orders"])
    }

    func testOpeningFailureIsReportedAndCanBeRetried() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }
        try Data().write(to: parent)
        let storage = PushRegistrationStorage(databaseURL: parent.appendingPathComponent("registration.sqlite"))
        XCTAssertThrowsError(try storage.setDesiredCategories(["orders"], site: "site"))
        try FileManager.default.removeItem(at: parent)
        try storage.setDesiredCategories(["orders"], site: "site")
        XCTAssertEqual(try storage.load(site: "site").desiredCategories, ["orders"])
    }

    private func temporaryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PushRegistrationStorageTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
