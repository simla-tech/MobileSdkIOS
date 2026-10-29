import Foundation
import SQLiteStorage

package struct PendingPushStatus: Equatable {
    package let id: UUID
    package let body: PushStatusRequestBody
    package let siteToken: String
    package let clientAPIEndpointURL: URL
    package var attempts: Int
    package var nextAttemptAt: Date

    package var event: PushStatusRetryEvent { .init(id: id, body: body) }

    package init(
        id: UUID,
        body: PushStatusRequestBody,
        siteToken: String,
        clientAPIEndpointURL: URL,
        attempts: Int,
        nextAttemptAt: Date
    ) {
        self.id = id
        self.body = body
        self.siteToken = siteToken
        self.clientAPIEndpointURL = clientAPIEndpointURL
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
    }
}

/// Uses Application Support in the current container; no App Group is involved.
package final class PushStatusRetryStorage: @unchecked Sendable {
    private let databaseURL: URL?
    private let lock = NSLock()
    private var database: SQLiteDatabase?

    package init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    package func loadPending() throws -> [PendingPushStatus] {
        try connection().withConnection { connection in
            try connection.query("""
                SELECT id, body, site_token, endpoint, attempts, next_attempt_at
                FROM push_status_retries ORDER BY next_attempt_at, id;
                """).map { row in
                    guard let id = row[0].string.flatMap(UUID.init(uuidString:)),
                          let body = row[1].data, let site = row[2].string,
                          let endpoint = row[3].string.flatMap(URL.init(string:)),
                          let attempts = row[4].integer, let nextAttempt = row[5].double else {
                        throw SQLiteStorageError(message: "Invalid push status retry record.")
                    }
                    return PendingPushStatus(
                        id: id, body: try JSONDecoder().decode(PushStatusRequestBody.self, from: body),
                        siteToken: site, clientAPIEndpointURL: endpoint, attempts: Int(attempts),
                        nextAttemptAt: Date(timeIntervalSince1970: nextAttempt)
                    )
                }
        }
    }

    package func save(_ entry: PendingPushStatus) throws {
        try connection().withConnection { connection in
            try connection.execute("""
                INSERT INTO push_status_retries
                    (id, body, site_token, endpoint, push_id, status, button_hash, attempts, next_attempt_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET attempts = excluded.attempts, next_attempt_at = excluded.next_attempt_at;
                """, bindings: [
                    .text(entry.id.uuidString), .blob(try JSONEncoder().encode(entry.body)), .text(entry.siteToken),
                    .text(entry.clientAPIEndpointURL.absoluteString), .text(entry.body.pushId), .text(entry.body.status.rawValue),
                    entry.body.buttonHash.map(SQLiteValue.text) ?? .null, .integer(Int64(entry.attempts)),
                    .real(entry.nextAttemptAt.timeIntervalSince1970)
                ])
        }
    }

    package func remove(_ id: UUID) throws {
        try connection().withConnection { connection in
            try connection.execute("DELETE FROM push_status_retries WHERE id = ?;", bindings: [.text(id.uuidString)])
        }
    }

    private func connection() throws -> SQLiteDatabase {
        lock.lock()
        defer { lock.unlock() }
        if let database { return database }
        let url = try databaseURL ?? SQLiteDatabase.applicationSupportURL(fileName: "crm_push_status_retries.sqlite")
        let opened = try SQLiteDatabase(url: url)
        try opened.migrate(["""
            CREATE TABLE push_status_retries (
                id TEXT PRIMARY KEY NOT NULL,
                body BLOB NOT NULL,
                site_token TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                push_id TEXT NOT NULL,
                status TEXT NOT NULL,
                button_hash TEXT,
                attempts INTEGER NOT NULL,
                next_attempt_at REAL NOT NULL
            );
            CREATE UNIQUE INDEX push_status_retries_identity ON push_status_retries
                (site_token, endpoint, push_id, status, COALESCE(button_hash, ''), (button_hash IS NULL));
            CREATE INDEX push_status_retries_next_attempt ON push_status_retries(next_attempt_at);
            """])
        database = opened
        return opened
    }
}
