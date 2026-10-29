import Foundation

/// Configuration used by SessionRuntime to call the client API.
package struct SessionConfig: Equatable, Sendable {

    /// Site token sent to the backend as the `X-Site-Token` header.
    package let siteToken: String
    package let endpoints: APIEndpoints

    /// Creates SessionRuntime configuration.
    package init(siteToken: String, baseURL: String = CrmSdkConfig.defaultBaseURL) {
        self.siteToken = siteToken
        self.endpoints = APIEndpoints(baseURL: baseURL)
    }
}
