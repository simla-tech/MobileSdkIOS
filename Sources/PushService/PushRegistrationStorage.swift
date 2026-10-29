import Foundation
import SQLiteStorage

/// Registration state is local to the application's container and isolated by site.
package final class PushRegistrationStorage: @unchecked Sendable {
    package struct State: Equatable {
        package var fingerprint: String?
        package var desiredCategories: [String]?
        package var confirmedCategories: [String]?
        package var systemCategories: [String]?

        package init(
            fingerprint: String? = nil,
            desiredCategories: [String]? = nil,
            confirmedCategories: [String]? = nil,
            systemCategories: [String]? = nil
        ) {
            self.fingerprint = fingerprint
            self.desiredCategories = desiredCategories
            self.confirmedCategories = confirmedCategories
            self.systemCategories = systemCategories
        }
    }

    private let databaseURL: URL?
    private let lock = NSLock()
    private var database: SQLiteDatabase?

    package init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    package func load(site: String) throws -> State {
        try connection().withConnection { try load(site: site, connection: $0) }
    }

    /// Saves the new list and returns the previous list in one transaction.
    @discardableResult
    package func setDesiredCategories(_ categories: [String], site: String) throws -> [String] {
        try connection().transaction { connection in
            let previous = try load(site: site, connection: connection).desiredCategories ?? []
            try connection.execute("""
                INSERT INTO push_registration (site, desired_categories) VALUES (?, ?)
                ON CONFLICT(site) DO UPDATE SET desired_categories = excluded.desired_categories;
                """, bindings: [.text(site), .blob(try JSONEncoder().encode(categories))])
            return previous
        }
    }

    package func setSystemCategories(_ categories: [String], site: String) throws {
        try connection().withConnection { connection in
            try connection.execute("""
                INSERT INTO push_registration (site, system_categories) VALUES (?, ?)
                ON CONFLICT(site) DO UPDATE SET system_categories = excluded.system_categories;
                """, bindings: [.text(site), .blob(try JSONEncoder().encode(categories))])
        }
    }

    package func invalidateFingerprint(site: String) throws {
        try connection().withConnection { connection in
            try connection.execute("UPDATE push_registration SET fingerprint = NULL WHERE site = ?;", bindings: [.text(site)])
        }
    }

    /// The fingerprint and confirmed list always describe the same accepted request.
    package func confirm(fingerprint: String, categories: [String], site: String) throws {
        try connection().withConnection { connection in
            try connection.execute("""
                INSERT INTO push_registration (site, fingerprint, confirmed_categories) VALUES (?, ?, ?)
                ON CONFLICT(site) DO UPDATE SET fingerprint = excluded.fingerprint,
                    confirmed_categories = excluded.confirmed_categories;
                """, bindings: [.text(site), .text(fingerprint), .blob(try JSONEncoder().encode(categories))])
        }
    }

    private func load(site: String, connection: SQLiteConnection) throws -> State {
        guard let row = try connection.query("""
            SELECT fingerprint, desired_categories, confirmed_categories, system_categories
            FROM push_registration WHERE site = ?;
            """, bindings: [.text(site)]).first else { return State() }
        func categories(_ value: SQLiteValue) throws -> [String]? {
            guard let data = value.data else { return nil }
            return try JSONDecoder().decode([String].self, from: data)
        }
        return try State(fingerprint: row[0].string, desiredCategories: categories(row[1]),
                         confirmedCategories: categories(row[2]), systemCategories: categories(row[3]))
    }

    private func connection() throws -> SQLiteDatabase {
        lock.lock()
        defer { lock.unlock() }
        if let database { return database }
        let url = try databaseURL ?? SQLiteDatabase.applicationSupportURL(fileName: "crm_push_registration.sqlite")
        let opened = try SQLiteDatabase(url: url)
        try opened.migrate(["""
            CREATE TABLE push_registration (
                site TEXT PRIMARY KEY NOT NULL,
                fingerprint TEXT,
                desired_categories BLOB,
                confirmed_categories BLOB,
                system_categories BLOB
            );
            """])
        database = opened
        return opened
    }
}
