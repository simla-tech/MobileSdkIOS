import Foundation

/// Queue and collector updates. Delivery means the collector response reported no error for the event.
/// Callbacks may arrive off the main thread.
public enum TrackerEventUpdate: Equatable, Sendable {
    /// Event IDs accepted into the startup buffer or saved to the persistent queue.
    case queued([String])
    /// Event IDs and the exact outgoing JSON body, without HTTP headers.
    /// The payload may contain personal data.
    case sending([String], payload: String)
    /// Event IDs for which the collector response reported no error.
    case delivered([String])
    /// Event IDs retained for a later attempt and the reason for retrying.
    case retryScheduled([String], TrackerError)
    /// Event ID permanently rejected by the collector or local size limit.
    case rejected(String, TrackerError)
    /// Event IDs removed from the queue and the reason for removal.
    case dropped([String], String)
}
