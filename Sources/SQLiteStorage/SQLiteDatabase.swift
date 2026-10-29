import Foundation
import SQLite3

/// A serialized connection to one database in the current process's container.
package final class SQLiteDatabase: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    package static func applicationSupportURL(fileName: String) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(fileName)
    }

    package init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        connection = try SQLiteConnection(url: url)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    package func withConnection<T>(_ operation: (SQLiteConnection) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation(connection)
    }

    package func transaction<T>(_ operation: (SQLiteConnection) throws -> T) throws -> T {
        try withConnection { connection in
            try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                let result = try operation(connection)
                try connection.execute("COMMIT;")
                return result
            } catch {
                try? connection.execute("ROLLBACK;")
                throw error
            }
        }
    }

    /// Each array entry advances user_version by one, atomically with its schema changes.
    package func migrate(_ migrations: [String]) throws {
        try transaction { connection in
            let version = Int(try connection.query("PRAGMA user_version;")[0][0].integer ?? 0)
            guard version >= 0, version <= migrations.count else {
                throw SQLiteStorageError(message: "Unsupported SQLite schema version: \(version).")
            }
            for index in version..<migrations.count {
                try connection.executeScript(migrations[index])
                try connection.execute("PRAGMA user_version = \(index + 1);")
            }
        }
    }
}

package enum SQLiteValue: Equatable {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)

    package var string: String? { if case .text(let value) = self { return value }; return nil }
    package var integer: Int64? { if case .integer(let value) = self { return value }; return nil }
    package var double: Double? { if case .real(let value) = self { return value }; return nil }
    package var data: Data? { if case .blob(let value) = self { return value }; return nil }
}

/// Only use a connection inside SQLiteDatabase.withConnection or SQLiteDatabase.transaction.
package final class SQLiteConnection {
    private let handle: OpaquePointer
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    package init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database."
            sqlite3_close(database)
            throw SQLiteStorageError(message: message)
        }
        handle = database
        sqlite3_busy_timeout(handle, 1_000)
    }

    deinit { sqlite3_close(handle) }

    package func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    package func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [[SQLiteValue]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return rows
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { index in
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
                    case SQLITE_TEXT:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        let bytes = UnsafeBufferPointer(start: sqlite3_column_text(statement, index), count: count)
                        return .text(String(decoding: bytes, as: UTF8.self))
                    case SQLITE_BLOB:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        guard let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
                        return .blob(Data(bytes: bytes, count: count))
                    default: return .null
                    }
                })
            default: throw failure()
            }
        }
    }

    package func executeScript(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            sqlite3_finalize(prepared)
            throw failure()
        }
        do {
            guard sqlite3_bind_parameter_count(statement) == bindings.count else {
                throw SQLiteStorageError(message: "SQLite binding count does not match the statement.")
            }
            for (offset, value) in bindings.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .null: result = sqlite3_bind_null(statement, index)
                case .text(let value):
                    result = sqlite3_bind_text(statement, index, value, Int32(value.utf8.count), Self.transient)
                case .integer(let value): result = sqlite3_bind_int64(statement, index, value)
                case .real(let value): result = sqlite3_bind_double(statement, index, value)
                case .blob(let value):
                    result = value.isEmpty ? sqlite3_bind_zeroblob(statement, index, 0) : value.withUnsafeBytes {
                        sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient)
                    }
                }
                guard result == SQLITE_OK else { throw failure() }
            }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func failure() -> SQLiteStorageError {
        SQLiteStorageError(message: String(cString: sqlite3_errmsg(handle)))
    }
}

package struct SQLiteStorageError: Error, Equatable, LocalizedError {
    package let message: String
    package init(message: String) { self.message = message }
    package var errorDescription: String? { message }
}
