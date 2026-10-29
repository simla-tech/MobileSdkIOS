import Foundation
import XCTest
@testable import PushNotificationExtension

final class PushStatusRetryStorageTests: XCTestCase {
    func testRetryStateSurvivesReopeningAndIndividualUpdatesPreserveOtherEntries() throws {
        let url = temporaryURL()
        var first = entry(pushID: "first")
        let second = entry(pushID: "second")
        do {
            let storage = PushStatusRetryStorage(databaseURL: url)
            try storage.save(first)
            try storage.save(second)
            first.attempts = 4
            first.nextAttemptAt = Date(timeIntervalSince1970: 5_000)
            try storage.save(first)
        }
        let reopened = PushStatusRetryStorage(databaseURL: url)
        XCTAssertEqual(try reopened.loadPending(), [second, first])
        try reopened.remove(first.id)
        XCTAssertEqual(try reopened.loadPending(), [second])
    }

    func testDuplicateStatusDoesNotReplaceOriginalTimeOrAttemptBudget() throws {
        let url = temporaryURL()
        let storage = PushStatusRetryStorage(databaseURL: url)
        let first = entry(pushID: "push")
        var duplicate = entry(pushID: "push")
        duplicate.attempts = 3
        XCTAssertNotEqual(first.id, duplicate.id)
        try storage.save(first)
        XCTAssertThrowsError(try storage.save(duplicate))
        XCTAssertEqual(try storage.loadPending(), [first])
        try storage.save(entry(pushID: "push", site: "other"))
        try storage.save(entry(pushID: "push", endpoint: "https://other.example.com/api/client/v1"))
        try storage.save(entry(pushID: "push", buttonHash: ""))
        XCTAssertEqual(try storage.loadPending().count, 4)
    }

    func testSeparateContainerPathsHaveIndependentQueues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = PushStatusRetryStorage(databaseURL: root.appendingPathComponent("app/crm_push_status_retries.sqlite"))
        let extensionStorage = PushStatusRetryStorage(databaseURL: root.appendingPathComponent("extension/crm_push_status_retries.sqlite"))
        let appEntry = entry(pushID: "push")
        let extensionEntry = entry(pushID: "push")
        try app.save(appEntry)
        try extensionStorage.save(extensionEntry)
        try app.remove(appEntry.id)
        XCTAssertTrue(try app.loadPending().isEmpty)
        XCTAssertEqual(try extensionStorage.loadPending(), [extensionEntry])
    }

    private func entry(
        pushID: String, site: String = "site", endpoint: String = "https://c.retailcrm.tech/api/client/v1", buttonHash: String? = nil
    ) -> PendingPushStatus {
        .init(id: UUID(), body: .init(changedAt: 100, pushId: pushID, status: .clicked, buttonHash: buttonHash),
              siteToken: site, clientAPIEndpointURL: URL(string: endpoint)!, attempts: 1,
              nextAttemptAt: Date(timeIntervalSince1970: 1_000))
    }

    private func temporaryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PushStatusRetryStorageTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
