import Foundation

/// Backend defaults shared by the application SDK and notification extension.
public enum SDKBackend {
    public static let defaultBaseURL = "https://c.retailcrm.tech"
}

package struct BackendEndpoints: Equatable, Sendable {
    package let clientAPIEndpointURL: URL
    package let clientWebSocketEndpointURL: URL

    package init(baseURL: String = SDKBackend.defaultBaseURL) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.query == nil, components.fragment == nil else {
            preconditionFailure("baseURL must be an absolute HTTP(S) URL without query or fragment.")
        }
        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if !components.path.hasSuffix("/api/client/v1") {
            components.path += "/api/client/v1"
        }
        guard let apiURL = components.url else {
            preconditionFailure("Invalid baseURL.")
        }
        clientAPIEndpointURL = apiURL
        components.scheme = scheme == "https" ? "wss" : "ws"
        components.path += "/ws"
        clientWebSocketEndpointURL = components.url!
    }
}
