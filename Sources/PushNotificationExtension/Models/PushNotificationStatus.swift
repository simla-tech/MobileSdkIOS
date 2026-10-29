import Foundation

/// Push status codes supported by the backend push status API.
public enum PushNotificationStatus: String, Codable, CaseIterable, Sendable {
    /// Notification was accepted for sending by the push pipeline.
    case sent

    /// Notification was delivered to the device or displayed by the app.
    case delivered

    /// User dismissed the notification from Notification Center.
    case swiped

    /// User opened the notification.
    case clicked

    /// Notification could not be delivered.
    case undelivered
}
