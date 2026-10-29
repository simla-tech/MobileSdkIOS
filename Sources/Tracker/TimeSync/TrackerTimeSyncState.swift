import Foundation

/// Tracker server time synchronization state.
package struct TrackerTimeSyncState: Equatable, Sendable {

    /// Server timestamp received from `connect.ts` or `GET /ts`.
    package let serverTimestamp: Date

    /// Local date when `serverTimestamp` was received.
    package let syncedAt: Date

    package init(serverTimestamp: Date, syncedAt: Date) {
        self.serverTimestamp = serverTimestamp
        self.syncedAt = syncedAt
    }
}
