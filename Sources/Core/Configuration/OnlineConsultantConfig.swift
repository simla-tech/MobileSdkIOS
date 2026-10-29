import Foundation

/// Defines local SDK settings used to connect to the Online Consultant backend and manage chat state.
public struct OnlineConsultantConfig: Sendable {

    /// The timeout, in seconds, used while opening the WebSocket connection.
    public let connectTimeout: TimeInterval

    /// A Boolean value that determines whether the SDK reconnects the WebSocket after failures.
    /// Foreground restoration after a background pause is independent of this setting.
    public let autoReconnectWebSocket: Bool

    /// The delay, in seconds, before the SDK retries a failed WebSocket subscription.
    /// Does not delay restoration when the application returns to the foreground.
    public let webSocketReconnectDelay: TimeInterval

    /// The number of messages requested by default when loading chat history pages.
    ///
    /// The SDK clamps this value to the `1...1000` range before sending it as the `limit` query item.
    public let messagesPageSize: Int

    /// The target number of messages the SDK tries to have after the initial connection.
    ///
    /// If the `connect` response contains fewer messages, the SDK loads the remaining amount with
    /// `GET /messages`. The SDK clamps this value to the `0...1000` range.
    public let initialMessagesLimit: Int

    /// The local disk cache policy used for cached file and image data.
    public let cachePolicy: OnlineConsultantCachePolicy

    /// Creates configuration for the OnlineConsultant chat module.
    ///
    /// - Parameters:
    ///   - connectTimeout: The timeout, in seconds, used while opening the WebSocket connection.
    ///   - autoReconnectWebSocket: Whether the SDK should reconnect the WebSocket after failures.
    ///   - webSocketReconnectDelay: The delay, in seconds, before retrying a failed WebSocket
    ///     subscription.
    ///   - messagesPageSize: The default page size for `GET /messages` history requests.
    ///   - initialMessagesLimit: The target number of messages to load during the initial connection.
    ///   - cachePolicy: The local disk cache policy for cached file and image data.
    public init(
        connectTimeout: TimeInterval = 30,
        autoReconnectWebSocket: Bool = true,
        webSocketReconnectDelay: TimeInterval = 3,
        messagesPageSize: Int = 50,
        initialMessagesLimit: Int = 50,
        cachePolicy: OnlineConsultantCachePolicy = OnlineConsultantCachePolicy()
    ) {
        self.connectTimeout = connectTimeout
        self.autoReconnectWebSocket = autoReconnectWebSocket
        self.webSocketReconnectDelay = webSocketReconnectDelay
        self.messagesPageSize = messagesPageSize
        self.initialMessagesLimit = initialMessagesLimit
        self.cachePolicy = cachePolicy
    }
}
