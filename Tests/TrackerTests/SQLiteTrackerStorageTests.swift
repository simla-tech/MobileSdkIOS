import Foundation
import SQLite3
import XCTest
@testable import Tracker

final class SQLiteTrackerStorageTests: XCTestCase {
    func testOversizedEvictsOldestAndSurvivesReopening() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let storage = try SQLiteTrackerStorage(databaseURL: url)
            try storage.activateScope(siteToken: "site", userToken: "user")
            for index in 0..<55 {
                let event = TrackerEvent(id: "event-\(index)", type: "click")
                try storage.appendPendingEvent(event, dropping: [])
                try storage.moveToOversized(event)
            }
            XCTAssertTrue(try storage.loadPendingEvents().isEmpty)
        }
        let reopened = try SQLiteTrackerStorage(databaseURL: url)
        try reopened.activateScope(siteToken: "site", userToken: "user")
        XCTAssertEqual(try reopened.loadOversizedEventIDs(), (5..<55).map { "event-\($0)" })
    }

    func testOwnerChangeAfterRestartDiscardsBothQueues() throws {
        for newOwner in [("site", "other-user"), ("other-site", "user")] {
            let url = temporaryURL()
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let storage = try SQLiteTrackerStorage(databaseURL: url)
                let first = TrackerEvent(id: "pending", type: "click")
                let second = TrackerEvent(id: "second", type: "click")
                XCTAssertThrowsError(try storage.appendPendingEvent(first, dropping: []))
                try storage.activateScope(siteToken: "site", userToken: "user")
                try storage.appendPendingEvent(first, dropping: [])
                try storage.appendPendingEvent(second, dropping: [])
                XCTAssertEqual(try storage.loadPendingEvents().map(\.id), ["pending", "second"])
                try storage.moveToOversized(TrackerEvent(id: "large", type: "click"))
            }
            let reopened = try SQLiteTrackerStorage(databaseURL: url)
            try reopened.activateScope(siteToken: newOwner.0, userToken: newOwner.1)
            XCTAssertTrue(try reopened.loadPendingEvents().isEmpty)
            XCTAssertTrue(try reopened.loadOversizedEventIDs().isEmpty)
            try reopened.activateScope(siteToken: "site", userToken: "user")
            XCTAssertTrue(try reopened.loadPendingEvents().isEmpty)
            XCTAssertTrue(try reopened.loadOversizedEventIDs().isEmpty)
        }
    }

    func testLegacyDatabasePrunesOtherOwnersAndOversizedOverflow() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let storage = try SQLiteTrackerStorage(databaseURL: url)
            try storage.activateScope(siteToken: "site", userToken: "user")
            try storage.appendPendingEvent(TrackerEvent(id: "keep", type: "click"), dropping: [])
        }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        // Reproduce the old schema's multiple owners and unbounded quarantine.
        XCTAssertEqual(sqlite3_exec(database, """
            INSERT INTO tracker_events VALUES ('old-owner', 'discard', 0, '{}');
            WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM numbers WHERE n < 59)
            INSERT INTO tracker_oversized_events (scope_hash, event_id, payload)
            SELECT (SELECT scope_hash FROM tracker_events WHERE event_id = 'keep'), 'large-' || n, '{}'
            FROM numbers ORDER BY n;
            INSERT INTO tracker_oversized_events VALUES ('old-owner', 'discard-large', '{}');
            """, nil, nil, nil), SQLITE_OK)
        let storage = try SQLiteTrackerStorage(databaseURL: url)
        try storage.activateScope(siteToken: "site", userToken: "user")
        XCTAssertEqual(try storage.loadPendingEvents().map(\.id), ["keep"])
        XCTAssertEqual(try storage.loadOversizedEventIDs(), (10..<60).map { "large-\($0)" })
        try storage.activateScope(siteToken: "site", userToken: "another-user")
        XCTAssertTrue(try storage.loadOversizedEventIDs().isEmpty)
    }

    func testFailedOwnerChangeRollsBackBothQueues() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = try SQLiteTrackerStorage(databaseURL: url)
        try storage.activateScope(siteToken: "site", userToken: "user")
        try storage.appendPendingEvent(TrackerEvent(id: "pending", type: "click"), dropping: [])
        try storage.moveToOversized(TrackerEvent(id: "large", type: "click"))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TRIGGER fail_cleanup BEFORE DELETE ON tracker_oversized_events
            BEGIN SELECT RAISE(FAIL, 'test cleanup failure'); END;
            """, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try storage.activateScope(siteToken: "site", userToken: "other"))
        XCTAssertEqual(try storage.loadPendingEvents().map(\.id), ["pending"])
        XCTAssertEqual(try storage.loadOversizedEventIDs(), ["large"])
        XCTAssertThrowsError(try storage.clearForIdentityChange())
        XCTAssertEqual(try storage.loadPendingEvents().map(\.id), ["pending"])
        XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER fail_cleanup;", nil, nil, nil), SQLITE_OK)
        try storage.clearForIdentityChange()
        try storage.activateScope(siteToken: "site", userToken: "user")
        XCTAssertTrue(try storage.loadPendingEvents().isEmpty)
        XCTAssertTrue(try storage.loadOversizedEventIDs().isEmpty)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString).sqlite")
    }
}
