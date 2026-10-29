import Foundation
import XCTest
@testable import SQLiteStorage

final class SQLiteDatabaseTests: XCTestCase {
    func testValuesSurviveReopeningAndDatabaseIsExcludedFromBackup() throws {
        let url = temporaryURL()
        let values: [SQLiteValue] = [.null, .text("Текст ' ?\u{0} 🌍"), .integer(Int64.max), .real(12.5), .blob(Data([0, 255])), .blob(Data())]
        do {
            let database = try SQLiteDatabase(url: url)
            try database.migrate(["CREATE TABLE sample (a, b, c, d, e, f);"])
            try database.withConnection { try $0.execute("INSERT INTO sample VALUES (?, ?, ?, ?, ?, ?);", bindings: values) }
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        let reopened = try SQLiteDatabase(url: url)
        XCTAssertEqual(try reopened.withConnection { try $0.query("SELECT * FROM sample;") }, [values])
    }

    func testTransactionFailureRollsBackAllWrites() throws {
        let url = temporaryURL()
        let database = try SQLiteDatabase(url: url)
        try database.migrate(["CREATE TABLE sample (id INTEGER PRIMARY KEY);"])
        XCTAssertThrowsError(try database.transaction { connection in
            try connection.execute("INSERT INTO sample VALUES (1);")
            try connection.execute("INSERT INTO sample VALUES (1);")
        })
        XCTAssertTrue(try database.withConnection { try $0.query("SELECT * FROM sample;").isEmpty })
        try database.transaction { try $0.execute("INSERT INTO sample VALUES (2);") }
        XCTAssertEqual(try database.withConnection { try $0.query("SELECT id FROM sample;") }, [[.integer(2)]])
    }

    func testFailedMigrationRollsBackSchemaAndVersionAndCanBeRetried() throws {
        let url = temporaryURL()
        let database = try SQLiteDatabase(url: url)
        XCTAssertThrowsError(try database.migrate(["CREATE TABLE sample (id); INSERT INTO missing VALUES (1);"]))
        XCTAssertEqual(try database.withConnection { try $0.query("PRAGMA user_version;") }, [[.integer(0)]])
        try database.migrate(["CREATE TABLE sample (id);"])
        try database.migrate(["CREATE TABLE sample (id);", "ALTER TABLE sample ADD COLUMN name TEXT;"])
        XCTAssertEqual(try database.withConnection { try $0.query("PRAGMA user_version;") }, [[.integer(2)]])
        XCTAssertThrowsError(try database.migrate(["CREATE TABLE sample (id);"]))
    }

    func testConcurrentTransactionsDoNotLoseUpdates() throws {
        let url = temporaryURL()
        let database = try SQLiteDatabase(url: url)
        try database.migrate(["CREATE TABLE counter (value INTEGER); INSERT INTO counter VALUES (0);"])
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            do {
                try database.transaction { connection in
                    let value = try connection.query("SELECT value FROM counter;")[0][0].integer!
                    try connection.execute("UPDATE counter SET value = ?;", bindings: [.integer(value + 1)])
                }
            } catch { XCTFail(error.localizedDescription) }
        }
        XCTAssertEqual(try database.withConnection { try $0.query("SELECT value FROM counter;") }, [[.integer(50)]])
    }

    func testDifferentFilesKeepIndependentSchemasAndData() throws {
        let firstURL = temporaryURL()
        let secondURL = temporaryURL()
        let first = try SQLiteDatabase(url: firstURL)
        let second = try SQLiteDatabase(url: secondURL)
        try first.migrate(["CREATE TABLE sample (id); INSERT INTO sample VALUES (1);"])
        try second.migrate(["CREATE TABLE sample (id);"])
        XCTAssertTrue(try second.withConnection { try $0.query("SELECT * FROM sample;").isEmpty })
        XCTAssertEqual(try first.withConnection { try $0.query("SELECT * FROM sample;") }, [[.integer(1)]])
    }

    private func temporaryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SQLiteDatabaseTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
