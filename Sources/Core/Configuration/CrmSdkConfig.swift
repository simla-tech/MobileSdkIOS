import Foundation
import SDKConfiguration

/// Shared configuration for Consultant SDK and its feature modules.
public struct CrmSdkConfig: Sendable {
    /// Production backend used when no custom URL is provided.
    public static let defaultBaseURL = SDKBackend.defaultBaseURL

    /// Backend HTTP(S) URL, with or without the `/api/client/v1` suffix.
    public let baseURL: String

    /// Site token sent to the backend as the `X-Site-Token` header.
    public let siteToken: String

    /// Default timeout for SDK network requests.
    public let requestTimeout: TimeInterval

    /// Default maximum duration for SDK resource requests.
    public let resourceTimeout: TimeInterval

    /// Optional HTTP observer; no events are retained by the SDK.
    public let networkObserver: (any CrmSdkNetworkObserver)?

    public let consultantConfig: OnlineConsultantConfig

    /// Tracker batching and time synchronization settings.
    public let trackerConfig: TrackerConfig

    /// Creates shared settings for the SDK and its modules.
    ///
    /// - Parameters:
    ///   - siteToken: Site token sent to the backend in `X-Site-Token`.
    ///   - baseURL: Absolute HTTP(S) backend URL without query or fragment.
    ///   - requestTimeout: Timeout for receiving data in an HTTP request, in seconds.
    ///   - resourceTimeout: Maximum duration of an HTTP request, in seconds.
    ///   - consultantConfig: Optional chat configuration; uses defaults when omitted.
    ///   - trackerConfig: Optional tracker configuration; uses defaults when omitted.
    ///   - networkObserver: Receives HTTP events asynchronously, including the initial connect request.
    public init(
        siteToken: String,
        baseURL: String = CrmSdkConfig.defaultBaseURL,
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 60,
        consultantConfig: OnlineConsultantConfig? = nil,
        trackerConfig: TrackerConfig? = nil,
        networkObserver: (any CrmSdkNetworkObserver)? = nil
    ) {
        self.networkObserver = networkObserver
        self.siteToken = siteToken
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.consultantConfig = consultantConfig ?? OnlineConsultantConfig()
        self.trackerConfig = trackerConfig ?? TrackerConfig()
    }
}
