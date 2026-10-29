import Foundation

/// Packs whole events in order, leaving 1 KiB of headroom below the request limit.
package enum TrackerBatchBuilder {
    package static let requestLimit = 1_048_576
    package static let targetSize = requestLimit - 1_024

    /// Oversized individual events remain intact for the caller to reject.
    package static func batches(_ events: [TrackerEvent], targetSize: Int = targetSize) throws -> [[TrackerEvent]] {
        let encoder = JSONEncoder()
        var result: [[TrackerEvent]] = []
        var current: [TrackerEvent] = []
        var size = 2 // JSON array brackets.
        for event in events {
            let eventSize = try encoder.encode(event).count
            let separator = current.isEmpty ? 0 : 1
            if !current.isEmpty, size + separator + eventSize > targetSize {
                result.append(current)
                current = []
                size = 2
            }
            size += (current.isEmpty ? 0 : 1) + eventSize
            current.append(event)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
