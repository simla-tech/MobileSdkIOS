import Foundation

/// Configuration for tracker requests.
public struct TrackerConfig: Equatable, Sendable {

    /// Maximum number of events sent in one batch.
    public let batchSize: Int

    /// Interval, in seconds, between periodic sends. Set `0` to disable periodic sends.
    public let flushInterval: TimeInterval

    /// Interval, in seconds, between tracker server time synchronizations.
    public let timeSyncInterval: TimeInterval

    /// Creates tracker SDK configuration.
    ///
    /// - Parameters:
    ///   - batchSize: Maximum number of tracker events sent in one batch (clamped to 1...50).
    ///   - flushInterval: Interval between periodic sends in seconds; `0` disables them.
    ///   - timeSyncInterval: Interval between server time synchronizations in seconds.
    public init(
        batchSize: Int = 50,
        flushInterval: TimeInterval = 15,
        timeSyncInterval: TimeInterval = 60 * 60
    ) {
        self.batchSize = min(50, max(1, batchSize))
        self.flushInterval = flushInterval.isFinite ? min(86_400, max(0, flushInterval)) : 15
        self.timeSyncInterval = timeSyncInterval.isFinite ? min(86_400, max(0, timeSyncInterval)) : 3_600
    }
}
