import Foundation

/// Thread-safe storage for tracker server time synchronization.
package final class TrackerTimeSyncStore: @unchecked Sendable {

    private let lock = NSLock()
    private var state: TrackerTimeSyncState?

    package var currentState: TrackerTimeSyncState? {
        lock.withLock {
            state
        }
    }

    package init() {}

    package func setServerTimestamp(_ timestamp: String?, syncedAt: Date = Date()) {
        guard
            let timestamp,
            let serverTimestamp = Self.date(from: timestamp)
        else {
            return
        }

        lock.withLock {
            state = TrackerTimeSyncState(
                serverTimestamp: serverTimestamp,
                syncedAt: syncedAt
            )
        }
    }

    package func clear() {
        lock.withLock {
            state = nil
        }
    }

    package func shouldRefresh(now: Date = Date(), interval: TimeInterval) -> Bool {
        lock.withLock {
            guard let state else {
                return true
            }

            return now.timeIntervalSince(state.syncedAt) >= interval
        }
    }

    package func resolvedServerDate(now: Date = Date()) -> Date {
        lock.withLock {
            guard let state else {
                return now
            }

            let elapsed = max(0, now.timeIntervalSince(state.syncedAt))
            return state.serverTimestamp.addingTimeInterval(elapsed)
        }
    }

    private static func date(from timestamp: String) -> Date? {
        let timestamp = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !timestamp.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = formatter.date(from: timestamp) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}
