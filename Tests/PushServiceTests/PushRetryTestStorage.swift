import Foundation
import XCTest
@testable import PushNotificationExtension

extension XCTestCase {
    /// Each fixture owns its queue, so persisted retries cannot leak into another test or run.
    func isolatedRetryQueue() -> PushStatusRetryQueue {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PushRetryTests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return PushStatusRetryQueue(storage: .init(databaseURL: url), baseDelay: 3_600, monitorsNetwork: false)
    }
}
