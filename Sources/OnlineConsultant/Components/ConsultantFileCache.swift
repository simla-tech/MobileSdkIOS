import Core
import Foundation

/// Stores attachment bytes as files and their metadata in a separate SQLite database.
/// Filesystem operations are serialized with metadata updates; reconciliation repairs interrupted work.
package final class ConsultantFileCache: @unchecked Sendable {
    private let rootDirectory: URL
    private let filesDirectory: URL
    private let databaseURL: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let queue = DispatchQueue(label: "ConsultantSDK.FileCache")
    private var storage: ConsultantFileCacheStorage?

    package init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now
        let root = rootDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConsultantSDK", isDirectory: true)
        self.rootDirectory = root
        filesDirectory = root.appendingPathComponent("files", isDirectory: true)
        databaseURL = root.appendingPathComponent(ConsultantFileCacheStorage.databaseFileName)
        queue.sync {
            do {
                try storageUnsafe().transaction { try reconcileUnsafe($0) }
            } catch {
                log(error, operation: "reconcile")
            }
        }
    }

    /// Returns a cached file URL and updates its last access time.
    package func cachedFileURL(fileID: String) -> URL? {
        queue.sync {
            guard let fileID = normalizedFileID(fileID) else { return nil }
            do {
                return try storageUnsafe().transaction { records in
                    guard let entry = try existingEntryUnsafe(fileID: fileID, records: records) else { return nil }
                    try records.touch(fileID: fileID, at: now())
                    return filesDirectory.appendingPathComponent(entry.localFileName)
                }
            } catch {
                log(error, operation: "read")
                return nil
            }
        }
    }

    /// Publishes a new file version only after its metadata has been committed.
    @discardableResult
    package func store(
        data: Data,
        fileID: String,
        contentType: String? = nil,
        remoteURL: URL? = nil
    ) throws -> URL {
        try queue.sync {
            guard let fileID = normalizedFileID(fileID) else { throw ConsultantFileCacheError.emptyFileID }
            let storage = try storageUnsafe()
            let fileName = UUID().uuidString + ".data"
            let fileURL = filesDirectory.appendingPathComponent(fileName)
            var previousURL: URL?
            do {
                try storage.transaction { records in
                    let previous = try records.entry(fileID: fileID)
                    try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
                    try data.write(to: fileURL, options: .atomic)
                    let date = now()
                    try records.save(.init(
                        fileID: fileID, localFileName: fileName, remoteURL: remoteURL, contentType: contentType,
                        size: Int64(data.count), createdAt: previous?.createdAt ?? date, lastAccessedAt: date
                    ))
                    previousURL = previous.map { filesDirectory.appendingPathComponent($0.localFileName) }
                }
            } catch {
                // The previous version is still referenced if the transaction did not commit.
                do { try removeFileIfPresentUnsafe(fileURL) } catch { log(error, operation: "remove unpublished file") }
                throw error
            }
            if let previousURL {
                do { try removeFileIfPresentUnsafe(previousURL) } catch { log(error, operation: "remove superseded file") }
            }
            return fileURL
        }
    }

    package func updateRemoteURL(fileID: String, remoteURL: URL) throws {
        try queue.sync {
            guard let fileID = normalizedFileID(fileID) else { throw ConsultantFileCacheError.emptyFileID }
            let updated = try storageUnsafe().transaction { records in
                guard try existingEntryUnsafe(fileID: fileID, records: records) != nil else { return false }
                try records.updateRemoteURL(fileID: fileID, remoteURL: remoteURL, at: now())
                return true
            }
            guard updated else { throw ConsultantFileCacheError.missingEntry(fileID: fileID) }
        }
    }

    package func entry(fileID: String) -> ConsultantFileCacheEntry? {
        queue.sync {
            guard let fileID = normalizedFileID(fileID) else { return nil }
            do {
                return try storageUnsafe().transaction { try existingEntryUnsafe(fileID: fileID, records: $0) }
            } catch {
                log(error, operation: "read metadata")
                return nil
            }
        }
    }

    package func statistics() -> ConsultantCacheStatistics {
        queue.sync {
            do {
                return try storageUnsafe().transaction { records in
                    try removeMissingEntriesUnsafe(records)
                    return try records.statistics()
                }
            } catch {
                log(error, operation: "read statistics")
                return .init(fileCount: 0, totalDiskSizeBytes: 0)
            }
        }
    }

    @discardableResult
    package func trim(policy: OnlineConsultantCachePolicy) throws -> ConsultantCacheStatistics {
        try queue.sync {
            do {
                return try storageUnsafe().transaction { records in
                    try reconcileUnsafe(records)
                    if let age = policy.maxFileAge, age >= 0 {
                        for entry in try records.entries(olderThan: now().addingTimeInterval(-age)) {
                            try removeEntryUnsafe(entry, records: records)
                        }
                    }
                    if let maxSize = policy.maxDiskSizeBytes, maxSize >= 0 {
                        var size = try records.statistics().totalDiskSizeBytes
                        if size > maxSize {
                            for entry in try records.oldestEntries() {
                                guard size > maxSize else { break }
                                try removeEntryUnsafe(entry, records: records)
                                size -= entry.size
                            }
                        }
                    }
                    return try records.statistics()
                }
            } catch {
                repairMissingEntriesUnsafe()
                throw error
            }
        }
    }

    /// Clears attachments and metadata without unlinking an open SQLite database.
    package func removeAll() throws {
        try queue.sync {
            do {
                try storageUnsafe().transaction { records in
                    try records.removeAll()
                    try removeFileIfPresentUnsafe(filesDirectory)
                    try removeFileIfPresentUnsafe(rootDirectory.appendingPathComponent("manifest.json"))
                }
            } catch {
                repairMissingEntriesUnsafe()
                throw error
            }
        }
    }

    private func storageUnsafe() throws -> ConsultantFileCacheStorage {
        if let storage, fileManager.fileExists(atPath: databaseURL.path) { return storage }
        // The system may purge the Caches directory while this instance is still alive.
        storage = nil
        let opened = try ConsultantFileCacheStorage(url: databaseURL)
        storage = opened
        return opened
    }

    private func existingEntryUnsafe(
        fileID: String, records: ConsultantFileCacheStorage.Records
    ) throws -> ConsultantFileCacheEntry? {
        guard let entry = try records.entry(fileID: fileID) else { return nil }
        guard fileManager.fileExists(atPath: filesDirectory.appendingPathComponent(entry.localFileName).path) else {
            try records.remove(fileID: fileID)
            return nil
        }
        return entry
    }

    private func removeEntryUnsafe(_ entry: ConsultantFileCacheEntry, records: ConsultantFileCacheStorage.Records) throws {
        // A database error leaves the file untouched. A filesystem error rolls back the metadata deletion.
        try records.remove(fileID: entry.fileID)
        try removeFileIfPresentUnsafe(filesDirectory.appendingPathComponent(entry.localFileName))
    }

    private func removeMissingEntriesUnsafe(_ records: ConsultantFileCacheStorage.Records) throws {
        for entry in try records.entries() {
            if !fileManager.fileExists(atPath: filesDirectory.appendingPathComponent(entry.localFileName).path) {
                try records.remove(fileID: entry.fileID)
            }
        }
    }

    private func reconcileUnsafe(_ records: ConsultantFileCacheStorage.Records) throws {
        try removeMissingEntriesUnsafe(records)
        let referenced = Set(try records.entries().map(\.localFileName))
        if fileManager.fileExists(atPath: filesDirectory.path) {
            for url in try fileManager.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil) {
                if !referenced.contains(url.lastPathComponent) { try removeFileIfPresentUnsafe(url) }
            }
        }
        // The pre-release JSON format is discarded rather than migrated.
        try removeFileIfPresentUnsafe(rootDirectory.appendingPathComponent("manifest.json"))
    }

    private func repairMissingEntriesUnsafe() {
        do {
            try storageUnsafe().transaction { try removeMissingEntriesUnsafe($0) }
        } catch {
            log(error, operation: "repair interrupted cleanup")
        }
    }

    private func removeFileIfPresentUnsafe(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Another cache instance may have already removed a superseded file.
        }
    }

    private func normalizedFileID(_ fileID: String) -> String? {
        let trimmed = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func log(_ error: Error, operation: String) {
        NSLog("RetailCRM consultant file cache could not %@: %@", operation, error.localizedDescription)
    }
}

/// Errors produced by the local file cache.
package enum ConsultantFileCacheError: Error, Equatable, LocalizedError {
    /// The provided file id is empty after trimming whitespace.
    case emptyFileID
    /// The cache does not contain an entry for the requested file id.
    case missingEntry(fileID: String)

    package var errorDescription: String? {
        switch self {
        case .emptyFileID:
            return ConsultantLocalization.fileCacheErrorEmptyFileID.localized
        case .missingEntry(let fileID):
            return ConsultantLocalization.fileCacheErrorMissingEntry.format(fileID)
        }
    }
}

/// Metadata describing a locally cached consultant file.
package struct ConsultantFileCacheEntry: Codable, Equatable {
    /// Backend file id used as the cache key.
    package let fileID: String
    /// File name used inside the SDK cache directory.
    package var localFileName: String
    /// Last known remote URL for this file, if it was resolved from the backend.
    package var remoteURL: URL?
    /// MIME content type, if known.
    package var contentType: String?
    /// Stored file size in bytes.
    package var size: Int64
    /// Date when the cache entry was first created.
    package var createdAt: Date
    /// Date when the cache entry was last read or updated.
    package var lastAccessedAt: Date

    package init(
        fileID: String,
        localFileName: String,
        remoteURL: URL?,
        contentType: String?,
        size: Int64,
        createdAt: Date,
        lastAccessedAt: Date
    ) {
        self.fileID = fileID
        self.localFileName = localFileName
        self.remoteURL = remoteURL
        self.contentType = contentType
        self.size = size
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}
