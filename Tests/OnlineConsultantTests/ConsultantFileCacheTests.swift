import Foundation
import SQLiteStorage
import XCTest
@testable import Core
@testable import OnlineConsultant

final class ConsultantFileCacheTests: XCTestCase {

    private var cacheRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsultantFileCacheTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let cacheRoot, FileManager.default.fileExists(atPath: cacheRoot.path) {
            try FileManager.default.removeItem(at: cacheRoot)
        }

        cacheRoot = nil
        try super.tearDownWithError()
    }

    func testStorePersistsFileAndRestoresAfterNewInstance() throws {
        let remoteURL = URL(string: "https://example.com/files/file-1")!
        let data = Data("image-data".utf8)
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)

        let fileURL = try cache.store(
            data: data,
            fileID: "file-1",
            contentType: "image/png",
            remoteURL: remoteURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), data)

        let restoredCache = ConsultantFileCache(rootDirectory: cacheRoot)
        let restoredURL = try XCTUnwrap(restoredCache.cachedFileURL(fileID: "file-1"))
        let restoredEntry = try XCTUnwrap(restoredCache.entry(fileID: "file-1"))

        XCTAssertEqual(try Data(contentsOf: restoredURL), data)
        XCTAssertEqual(restoredEntry.fileID, "file-1")
        XCTAssertEqual(restoredEntry.remoteURL, remoteURL)
        XCTAssertEqual(restoredEntry.contentType, "image/png")
        XCTAssertEqual(restoredEntry.size, Int64(data.count))
    }

    func testUpdateRemoteURLPersistsInDatabase() throws {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)
        let initialURL = URL(string: "https://example.com/files/old")!
        let updatedURL = URL(string: "https://example.com/files/new")!

        try cache.store(data: Data("file".utf8), fileID: "file-1", remoteURL: initialURL)
        try cache.updateRemoteURL(fileID: "file-1", remoteURL: updatedURL)

        let restoredCache = ConsultantFileCache(rootDirectory: cacheRoot)
        XCTAssertEqual(restoredCache.entry(fileID: "file-1")?.remoteURL, updatedURL)
    }

    func testStoreRejectsEmptyFileID() {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)

        XCTAssertThrowsError(try cache.store(data: Data(), fileID: "   ")) { error in
            XCTAssertEqual(error as? ConsultantFileCacheError, .emptyFileID)
        }
    }

    func testUpdateRemoteURLRejectsMissingEntry() {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)
        let remoteURL = URL(string: "https://example.com/files/file-1")!

        XCTAssertThrowsError(try cache.updateRemoteURL(fileID: "file-1", remoteURL: remoteURL)) { error in
            XCTAssertEqual(
                error as? ConsultantFileCacheError,
                .missingEntry(fileID: "file-1")
            )
        }
    }

    func testRemoveAllClearsFilesAndMetadata() throws {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)
        let fileURL = try cache.store(data: Data("file".utf8), fileID: "file-1")

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(cache.cachedFileURL(fileID: "file-1"))
        XCTAssertEqual(cache.statistics(), ConsultantCacheStatistics(fileCount: 0, totalDiskSizeBytes: 0))
    }

    func testTrimRemovesFilesOlderThanPolicyAge() throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let cache = ConsultantFileCache(
            rootDirectory: cacheRoot,
            now: { currentDate }
        )

        try cache.store(data: Data("old".utf8), fileID: "old-file")
        currentDate = Date(timeIntervalSince1970: 1_100)
        try cache.store(data: Data("new".utf8), fileID: "new-file")
        currentDate = Date(timeIntervalSince1970: 1_200)

        let statistics = try cache.trim(policy: OnlineConsultantCachePolicy(maxFileAge: 150))

        XCTAssertNil(cache.entry(fileID: "old-file"))
        XCTAssertNotNil(cache.entry(fileID: "new-file"))
        XCTAssertEqual(statistics.fileCount, 1)
        XCTAssertEqual(statistics.totalDiskSizeBytes, 3)
    }

    func testTrimRemovesLeastRecentlyAccessedFilesUntilSizeFits() throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let cache = ConsultantFileCache(
            rootDirectory: cacheRoot,
            now: { currentDate }
        )

        try cache.store(data: Data("111".utf8), fileID: "file-1")
        currentDate = Date(timeIntervalSince1970: 1_100)
        try cache.store(data: Data("2222".utf8), fileID: "file-2")
        currentDate = Date(timeIntervalSince1970: 1_200)
        try cache.store(data: Data("33333".utf8), fileID: "file-3")

        let statistics = try cache.trim(policy: OnlineConsultantCachePolicy(maxDiskSizeBytes: 9))

        XCTAssertNil(cache.entry(fileID: "file-1"))
        XCTAssertNotNil(cache.entry(fileID: "file-2"))
        XCTAssertNotNil(cache.entry(fileID: "file-3"))
        XCTAssertEqual(statistics.fileCount, 2)
        XCTAssertEqual(statistics.totalDiskSizeBytes, 9)
    }

    func testReplacingFilePreservesCreationDateAndRemovesPreviousVersion() throws {
        var date = Date(timeIntervalSince1970: 1_000.125)
        let cache = ConsultantFileCache(rootDirectory: cacheRoot, now: { date })
        let originalURL = try cache.store(data: Data("old".utf8), fileID: "file")
        date = Date(timeIntervalSince1970: 2_000.5)
        let replacementURL = try cache.store(data: Data("replacement".utf8), fileID: "file", contentType: "text/plain")
        XCTAssertNotEqual(originalURL, replacementURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        let reopened = ConsultantFileCache(rootDirectory: cacheRoot)
        let entry = try XCTUnwrap(reopened.entry(fileID: "file"))
        XCTAssertEqual(entry.createdAt, Date(timeIntervalSince1970: 1_000.125))
        XCTAssertEqual(entry.lastAccessedAt, date)
        XCTAssertEqual(entry.size, 11)
        XCTAssertEqual(entry.contentType, "text/plain")
        XCTAssertEqual(try Data(contentsOf: replacementURL), Data("replacement".utf8))
    }

    func testCachedFileAccessPersistsDateAndChangesEvictionOrder() throws {
        var date = Date(timeIntervalSince1970: 1_000)
        let cache = ConsultantFileCache(rootDirectory: cacheRoot, now: { date })
        try cache.store(data: Data("one".utf8), fileID: "first")
        date = Date(timeIntervalSince1970: 1_100)
        try cache.store(data: Data("two".utf8), fileID: "second")
        date = Date(timeIntervalSince1970: 1_200)
        XCTAssertNotNil(cache.cachedFileURL(fileID: "first"))
        let reopened = ConsultantFileCache(rootDirectory: cacheRoot)
        XCTAssertEqual(reopened.entry(fileID: "first")?.lastAccessedAt, date)
        try reopened.trim(policy: .init(maxDiskSizeBytes: 3))
        XCTAssertNotNil(reopened.entry(fileID: "first"))
        XCTAssertNil(reopened.entry(fileID: "second"))
    }

    func testClearCanBeFollowedByStoreAndIsVisibleToAnotherInstance() throws {
        let first = ConsultantFileCache(rootDirectory: cacheRoot)
        try first.store(data: Data("old".utf8), fileID: "old")
        let second = ConsultantFileCache(rootDirectory: cacheRoot)
        try first.removeAll()
        XCTAssertNil(second.entry(fileID: "old"))
        let url = try second.store(data: Data("new".utf8), fileID: "new")
        XCTAssertEqual(first.cachedFileURL(fileID: "new"), url)
        XCTAssertEqual(first.statistics(), .init(fileCount: 1, totalDiskSizeBytes: 3))
        try second.removeAll()
        XCTAssertEqual(first.statistics(), .init(fileCount: 0, totalDiskSizeBytes: 0))
    }

    func testOpeningReconcilesMissingFilesAndUnreferencedFiles() throws {
        var missingURL: URL!
        do {
            let cache = ConsultantFileCache(rootDirectory: cacheRoot)
            missingURL = try cache.store(data: Data("missing".utf8), fileID: "missing")
            try cache.store(data: Data("keep".utf8), fileID: "keep")
        }
        try FileManager.default.removeItem(at: missingURL)
        let orphanURL = cacheRoot.appendingPathComponent("files/interrupted-write.data")
        try Data("orphan".utf8).write(to: orphanURL)
        let reopened = ConsultantFileCache(rootDirectory: cacheRoot)
        XCTAssertNil(reopened.entry(fileID: "missing"))
        XCTAssertNil(reopened.cachedFileURL(fileID: "missing"))
        XCTAssertNotNil(reopened.entry(fileID: "keep"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertEqual(reopened.statistics(), .init(fileCount: 1, totalDiskSizeBytes: 4))
    }

    func testFailedMetadataReplacementKeepsOriginalFileAndDoesNotLeakNewFile() throws {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)
        let originalURL = try cache.store(data: Data("original".utf8), fileID: "file")
        let originalEntry = try XCTUnwrap(cache.entry(fileID: "file"))
        let database = try SQLiteDatabase(url: databaseURL)
        try database.withConnection { try $0.execute("""
            CREATE TRIGGER reject_replacement BEFORE UPDATE ON cache_files
            BEGIN SELECT RAISE(FAIL, 'test metadata failure'); END;
            """) }
        XCTAssertThrowsError(try cache.store(data: Data("new".utf8), fileID: "file"))
        XCTAssertEqual(cache.entry(fileID: "file"), originalEntry)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheRoot.appendingPathComponent("files").path).count, 1)
    }

    func testFailedMetadataDeletionLeavesFileUntouched() throws {
        let cache = ConsultantFileCache(rootDirectory: cacheRoot)
        let url = try cache.store(data: Data("keep".utf8), fileID: "file")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.withConnection { try $0.execute("""
            CREATE TRIGGER reject_deletion BEFORE DELETE ON cache_files
            BEGIN SELECT RAISE(FAIL, 'test deletion failure'); END;
            """) }
        XCTAssertThrowsError(try cache.trim(policy: .init(maxDiskSizeBytes: 0)))
        XCTAssertThrowsError(try cache.removeAll())
        XCTAssertEqual(try Data(contentsOf: url), Data("keep".utf8))
        XCTAssertNotNil(cache.entry(fileID: "file"))
    }

    func testPartialTrimFailureRetainsRemainingFileAndRepairsAlreadyRemovedEntries() throws {
        let manager = FailingCacheFileManager()
        var date = Date(timeIntervalSince1970: 1_000)
        let cache = ConsultantFileCache(rootDirectory: cacheRoot, fileManager: manager, now: { date })
        let firstURL = try cache.store(data: Data("one".utf8), fileID: "first")
        date = Date(timeIntervalSince1970: 1_100)
        let secondURL = try cache.store(data: Data("second".utf8), fileID: "second")
        manager.blockedURL = secondURL
        XCTAssertThrowsError(try cache.trim(policy: .init(maxDiskSizeBytes: 0)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertNil(cache.entry(fileID: "first"))
        XCTAssertNotNil(cache.entry(fileID: "second"))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second".utf8))
        XCTAssertEqual(cache.statistics(), .init(fileCount: 1, totalDiskSizeBytes: 6))
        manager.blockedURL = nil
        XCTAssertEqual(try cache.trim(policy: .init(maxDiskSizeBytes: 0)), .init(fileCount: 0, totalDiskSizeBytes: 0))
    }

    func testFailedClearRetainsMetadataAndCanBeRetried() throws {
        let manager = FailingCacheFileManager()
        let cache = ConsultantFileCache(rootDirectory: cacheRoot, fileManager: manager)
        let url = try cache.store(data: Data("keep".utf8), fileID: "file")
        manager.blockedURL = cacheRoot.appendingPathComponent("files", isDirectory: true)
        XCTAssertThrowsError(try cache.removeAll())
        XCTAssertEqual(cache.cachedFileURL(fileID: "file"), url)
        let reopened = ConsultantFileCache(rootDirectory: cacheRoot)
        XCTAssertNotNil(reopened.entry(fileID: "file"))
        manager.blockedURL = nil
        try cache.removeAll()
        XCTAssertNil(reopened.entry(fileID: "file"))
    }

    func testOpeningRemovesSupersededFileLeftByFailedFilesystemCleanup() throws {
        let manager = FailingCacheFileManager()
        let cache = ConsultantFileCache(rootDirectory: cacheRoot, fileManager: manager)
        let oldURL = try cache.store(data: Data("old".utf8), fileID: "file")
        manager.blockedURL = oldURL
        let newURL = try cache.store(data: Data("new".utf8), fileID: "file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        let reopened = ConsultantFileCache(rootDirectory: cacheRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(reopened.cachedFileURL(fileID: "file"), newURL)
        XCTAssertEqual(reopened.statistics(), .init(fileCount: 1, totalDiskSizeBytes: 3))
    }

    func testConcurrentInstancesDoNotDeleteFilesBeingPublished() throws {
        let root = try XCTUnwrap(cacheRoot)
        let first = ConsultantFileCache(rootDirectory: root)
        let second = ConsultantFileCache(rootDirectory: root)
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let cache = index.isMultiple(of: 2) ? first : second
            do {
                try cache.store(data: Data("file-\(index)".utf8), fileID: "id-\(index)")
                _ = ConsultantFileCache(rootDirectory: root).statistics()
            } catch { XCTFail(error.localizedDescription) }
        }
        let reopened = ConsultantFileCache(rootDirectory: root)
        for index in 0..<12 {
            let url = try XCTUnwrap(reopened.cachedFileURL(fileID: "id-\(index)"))
            XCTAssertEqual(try Data(contentsOf: url), Data("file-\(index)".utf8))
        }
        XCTAssertEqual(reopened.statistics().fileCount, 12)
    }

    private var databaseURL: URL {
        cacheRoot.appendingPathComponent(ConsultantFileCacheStorage.databaseFileName)
    }

}

private final class FailingCacheFileManager: FileManager, @unchecked Sendable {
    var blockedURL: URL?

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == blockedURL?.standardizedFileURL {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
