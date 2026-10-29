import CryptoKit
import Foundation
import SQLiteStorage

package final class SQLiteTrackerStorage {
    private static let databaseFileName = "crm_consultant_tracker.sqlite"
    private let database: SQLiteDatabase
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var activeScopeHash: String?

    package var hasActiveScope: Bool {
        lock.withLock { activeScopeHash != nil }
    }

    package convenience init() throws {
        try self.init(databaseURL: SQLiteDatabase.applicationSupportURL(fileName: Self.databaseFileName))
    }

    package init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try database.migrate(["""
            CREATE TABLE IF NOT EXISTS tracker_events (
                scope_hash TEXT NOT NULL,
                event_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                payload TEXT NOT NULL,
                PRIMARY KEY (scope_hash, event_id)
            );
            CREATE INDEX IF NOT EXISTS tracker_events_scope_position
                ON tracker_events(scope_hash, position);
            CREATE TABLE IF NOT EXISTS tracker_oversized_events (
                scope_hash TEXT NOT NULL,
                event_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                PRIMARY KEY (scope_hash, event_id)
            );
            """])
    }

    @discardableResult
    package func activateScope(siteToken: String, userToken: String) throws -> Bool {
        let scope = Self.scopeHash(siteToken: siteToken, userToken: userToken)
        return try lock.withLock {
            guard activeScopeHash != scope else { return false }
            try database.transaction { connection in
                for table in ["tracker_events", "tracker_oversized_events"] {
                    try connection.execute("DELETE FROM \(table) WHERE scope_hash != ?;", bindings: [.text(scope)])
                }
                try trimOversizedEvents(connection)
            }
            activeScopeHash = scope
            return true
        }
    }

    package func loadPendingEvents() throws -> [TrackerEvent] {
        try lock.withLock {
            let scope = try requireScope()
            return try database.withConnection { connection in
                try connection.query(
                    "SELECT payload FROM tracker_events WHERE scope_hash = ? ORDER BY position ASC;",
                    bindings: [.text(scope)]
                ).map { row in
                    guard let payload = row[0].string else {
                        throw SQLiteTrackerStorageError.sqlite(TrackerLocalization.sqliteEventPayloadMissing.localized)
                    }
                    return try decoder.decode(TrackerEvent.self, from: Data(payload.utf8))
                }
            }
        }
    }

    package func savePendingEvents(_ events: [TrackerEvent]) throws {
        try lock.withLock {
            let scope = try requireScope()
            try database.transaction { connection in
                try connection.execute("DELETE FROM tracker_events WHERE scope_hash = ?;", bindings: [.text(scope)])
                try insert(events, scope: scope, connection: connection)
            }
        }
    }

    package func appendPendingEvent(_ event: TrackerEvent, dropping ids: Set<String>) throws {
        try lock.withLock {
            let scope = try requireScope()
            try database.transaction { connection in
                try deleteEvents(ids: ids, scope: scope, connection: connection)
                let rows = try connection.query(
                    "SELECT COALESCE(MAX(position), -1) + 1 FROM tracker_events WHERE scope_hash = ?;",
                    bindings: [.text(scope)]
                )
                try insert([event], scope: scope, startingPosition: rows[0][0].integer ?? 0, connection: connection)
            }
        }
    }

    package func removePendingEvents(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try lock.withLock {
            let scope = try requireScope()
            try database.transaction { connection in
                try deleteEvents(ids: ids, scope: scope, connection: connection)
            }
        }
    }

    package func moveToOversized(_ event: TrackerEvent) throws {
        try lock.withLock {
            let scope = try requireScope()
            let payload = String(decoding: try encoder.encode(event), as: UTF8.self)
            try database.transaction { connection in
                try connection.execute(
                    "INSERT OR REPLACE INTO tracker_oversized_events (scope_hash, event_id, payload) VALUES (?, ?, ?);",
                    bindings: [.text(scope), .text(event.id), .text(payload)]
                )
                try deleteEvents(ids: [event.id], scope: scope, connection: connection)
                try trimOversizedEvents(connection)
            }
        }
    }

    package func loadOversizedEventIDs() throws -> [String] {
        try lock.withLock {
            let scope = try requireScope()
            return try database.withConnection { connection in
                try connection.query(
                    "SELECT event_id FROM tracker_oversized_events WHERE scope_hash = ? ORDER BY rowid ASC;",
                    bindings: [.text(scope)]
                ).map { row in
                    guard let id = row[0].string else {
                        throw SQLiteTrackerStorageError.sqlite(TrackerLocalization.sqliteEventPayloadMissing.localized)
                    }
                    return id
                }
            }
        }
    }

    package func clearOversizedEvents() throws {
        try lock.withLock {
            let scope = try requireScope()
            try database.withConnection { connection in
                try connection.execute("DELETE FROM tracker_oversized_events WHERE scope_hash = ?;", bindings: [.text(scope)])
            }
        }
    }

    /// Clears both queues before reconnecting as another customer, even if reconnect fails.
    package func clearForIdentityChange() throws {
        try lock.withLock {
            try database.transaction { connection in
                try connection.execute("DELETE FROM tracker_events;")
                try connection.execute("DELETE FROM tracker_oversized_events;")
            }
            activeScopeHash = nil
        }
    }

    private func requireScope() throws -> String {
        guard let activeScopeHash else {
            throw SQLiteTrackerStorageError.sqlite(TrackerLocalization.storageScopeInactive.localized)
        }
        return activeScopeHash
    }

    private func trimOversizedEvents(_ connection: SQLiteConnection) throws {
        try connection.execute("""
            DELETE FROM tracker_oversized_events WHERE rowid NOT IN (
                SELECT rowid FROM tracker_oversized_events ORDER BY rowid DESC LIMIT 50
            );
            """)
    }

    private func deleteEvents(ids: Set<String>, scope: String, connection: SQLiteConnection) throws {
        for id in ids {
            try connection.execute(
                "DELETE FROM tracker_events WHERE scope_hash = ? AND event_id = ?;", bindings: [.text(scope), .text(id)]
            )
        }
    }

    private func insert(
        _ events: [TrackerEvent], scope: String, startingPosition: Int64 = 0, connection: SQLiteConnection
    ) throws {
        for (position, event) in events.enumerated() {
            let payload = String(decoding: try encoder.encode(event), as: UTF8.self)
            try connection.execute(
                "INSERT OR REPLACE INTO tracker_events (scope_hash, event_id, position, payload) VALUES (?, ?, ?, ?);",
                bindings: [.text(scope), .text(event.id), .integer(startingPosition + Int64(position)), .text(payload)]
            )
        }
    }

    private static func scopeHash(siteToken: String, userToken: String) -> String {
        SHA256.hash(data: Data("\(siteToken)\u{0}\(userToken)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

package enum SQLiteTrackerStorageError: Error, Equatable, LocalizedError {
    case sqlite(String)

    package var errorDescription: String? {
        switch self {
        case .sqlite(let message): return message
        }
    }
}
