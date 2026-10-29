/// Realtime payload sent by the backend when consultant availability changes.
///
/// The event uses the `offline_status` type and contains only `is_offline`. The same offline flag
/// also appears in the connect response behaviour, but this model represents the websocket payload.
 package struct ConsultantOfflineStatus: Codable, Equatable, Sendable {

    /// Indicates whether managers for the current site are offline.
     package let isOffline: Bool

    /// Creates an offline status payload.
     package init(isOffline: Bool) {
        self.isOffline = isOffline
    }

    private enum CodingKeys: String, CodingKey {

        case isOffline = "is_offline"
    }
}
