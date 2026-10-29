import Foundation

/// Data passed to the application when a RetailCRM notification or its button is opened.
public struct NotificationAction {
    /// `click_action`, fallback `url` or `link`, or tapped button value; `nil` if absent.
    public let urlString: String?
    /// String and numeric push fields prefixed with `ca_`, without the prefix; `nil` if none were valid.
    public let customAttributes: [String: String]?

    /// Creates a notification action without converting the action string to `URL`.
    ///
    /// - Parameters:
    ///   - urlString: Action string supplied by the notification payload; it may be absent.
    ///   - customAttributes: Optional custom attributes from the notification payload.
    public init(urlString: String?, customAttributes: [String: String]?) {
        self.urlString = urlString
        self.customAttributes = customAttributes
    }
}
