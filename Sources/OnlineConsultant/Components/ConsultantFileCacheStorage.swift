import Core
import Foundation
import SQLiteStorage

/// Metadata only; attachment bytes remain in the adjacent files directory.
package final class ConsultantFileCacheStorage {
    package static let databaseFileName = "crm_consultant_cache.sqlite"
    private let database: SQLiteDatabase

    package init(url: URL) throws {
        database = try SQLiteDatabase(url: url)
        try database.migrate(["""
            CREATE TABLE cache_files (
                file_id TEXT PRIMARY KEY NOT NULL,
                local_file_name TEXT UNIQUE NOT NULL,
                remote_url TEXT,
                content_type TEXT,
                size INTEGER NOT NULL CHECK (size >= 0),
                created_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL
            );
            CREATE INDEX cache_files_last_accessed ON cache_files(last_accessed_at, created_at, file_id);
            """])
    }

    /// The write transaction also coordinates filesystem work across cache instances.
    package func transaction<T>(_ operation: (Records) throws -> T) throws -> T {
        try database.transaction { try operation(Records(connection: $0)) }
    }

    package struct Records {
        private let connection: SQLiteConnection
        private static let columns = "file_id, local_file_name, remote_url, content_type, size, created_at, last_accessed_at"

        package func entry(fileID: String) throws -> ConsultantFileCacheEntry? {
            try connection.query("SELECT \(Self.columns) FROM cache_files WHERE file_id = ?;", bindings: [.text(fileID)])
                .first.map(Self.decode)
        }

        package func entries() throws -> [ConsultantFileCacheEntry] {
            try connection.query("SELECT \(Self.columns) FROM cache_files;").map(Self.decode)
        }

        package func entries(olderThan date: Date) throws -> [ConsultantFileCacheEntry] {
            try connection.query(
                "SELECT \(Self.columns) FROM cache_files WHERE last_accessed_at < ?;",
                bindings: [.real(date.timeIntervalSince1970)]
            ).map(Self.decode)
        }

        package func oldestEntries() throws -> [ConsultantFileCacheEntry] {
            try connection.query(
                "SELECT \(Self.columns) FROM cache_files ORDER BY last_accessed_at, created_at, file_id;"
            ).map(Self.decode)
        }

        package func save(_ entry: ConsultantFileCacheEntry) throws {
            try connection.execute("""
                INSERT INTO cache_files (\(Self.columns)) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(file_id) DO UPDATE SET
                    local_file_name = excluded.local_file_name, remote_url = excluded.remote_url,
                    content_type = excluded.content_type, size = excluded.size,
                    created_at = excluded.created_at, last_accessed_at = excluded.last_accessed_at;
                """, bindings: [
                    .text(entry.fileID), .text(entry.localFileName),
                    entry.remoteURL.map { .text($0.absoluteString) } ?? .null,
                    entry.contentType.map(SQLiteValue.text) ?? .null, .integer(entry.size),
                    .real(entry.createdAt.timeIntervalSince1970), .real(entry.lastAccessedAt.timeIntervalSince1970)
                ])
        }

        package func touch(fileID: String, at date: Date) throws {
            try connection.execute(
                "UPDATE cache_files SET last_accessed_at = ? WHERE file_id = ?;",
                bindings: [.real(date.timeIntervalSince1970), .text(fileID)]
            )
        }

        package func updateRemoteURL(fileID: String, remoteURL: URL, at date: Date) throws {
            try connection.execute(
                "UPDATE cache_files SET remote_url = ?, last_accessed_at = ? WHERE file_id = ?;",
                bindings: [.text(remoteURL.absoluteString), .real(date.timeIntervalSince1970), .text(fileID)]
            )
        }

        package func remove(fileID: String) throws {
            try connection.execute("DELETE FROM cache_files WHERE file_id = ?;", bindings: [.text(fileID)])
        }

        package func removeAll() throws {
            try connection.execute("DELETE FROM cache_files;")
        }

        package func statistics() throws -> ConsultantCacheStatistics {
            let row = try connection.query("SELECT COUNT(*), COALESCE(SUM(size), 0) FROM cache_files;")[0]
            return .init(fileCount: Int(row[0].integer ?? 0), totalDiskSizeBytes: row[1].integer ?? 0)
        }

        private static func decode(_ row: [SQLiteValue]) throws -> ConsultantFileCacheEntry {
            guard let fileID = row[0].string, let fileName = row[1].string,
                  !fileName.isEmpty, fileName != ".", fileName != "..", !fileName.contains("/"),
                  let size = row[4].integer, let createdAt = row[5].double,
                  let lastAccessedAt = row[6].double else {
                throw SQLiteStorageError(message: "Invalid consultant file cache record.")
            }
            return .init(
                fileID: fileID, localFileName: fileName, remoteURL: row[2].string.flatMap(URL.init(string:)),
                contentType: row[3].string, size: size, createdAt: Date(timeIntervalSince1970: createdAt),
                lastAccessedAt: Date(timeIntervalSince1970: lastAccessedAt)
            )
        }

        package init(connection: SQLiteConnection) {
            self.connection = connection
        }
    }
}
