import Core
import Foundation

/// Component responsible for the SDK HTTP transport.
///
/// It defines request/response DTOs used by the client layer and provides the
/// URLSession-backed implementation for JSON requests and raw file uploads.
/// Executes HTTP requests used by the online consultant client.
package protocol ConsultantNetworkEngine: AnyObject {

    /// Sends a GET request and returns the raw HTTP response.
    func getJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse
    /// Sends a JSON POST request and returns the raw HTTP response.
    func postJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse
    /// Sends a raw POST request with an explicit content type.
    func postRaw(_ request: ConsultantRawHTTPRequest) async throws -> ConsultantHTTPResponse
}

/// Describes a JSON HTTP request sent by the SDK.
package struct ConsultantHTTPRequest: Equatable, Sendable {

    /// Absolute endpoint URL.
     package let url: URL
    /// HTTP headers applied to the request.
     package let headers: [String: String]
    /// Optional request body. Usually contains encoded JSON for POST requests.
     package let body: Data?

    /// Creates a JSON HTTP request descriptor.
     package init(
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// Describes a raw HTTP request sent by the SDK, usually for file uploads.
package struct ConsultantRawHTTPRequest: Equatable, Sendable {

    /// Absolute endpoint URL.
     package let url: URL
    /// HTTP headers applied to the request.
     package let headers: [String: String]
    /// Raw request body.
     package let body: Data
    /// MIME content type for the raw body.
     package let contentType: String

    /// Creates a raw HTTP request descriptor.
     package init(
        url: URL,
        headers: [String: String] = [:],
        body: Data,
        contentType: String
    ) {
        self.url = url
        self.headers = headers
        self.body = body
        self.contentType = contentType
    }
}

/// Raw HTTP response returned by a network engine.
package struct ConsultantHTTPResponse: Equatable, Sendable {

    /// Numeric HTTP status code.
     package let statusCode: Int
    /// Raw response body.
     package let body: Data

    /// Indicates whether the status code is in the 2xx success range.
     package var isSuccessful: Bool {
        (200..<300).contains(statusCode)
    }

    /// Creates an HTTP response descriptor.
     package init(
        statusCode: Int,
        body: Data
    ) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// URLSession-backed implementation of the HTTP network engine.
package final class URLSessionConsultantNetworkEngine: ConsultantNetworkEngine {

    private let session: URLSession

    /// Creates an engine backed by the SDK's shared URL session.
    package convenience init() {
        self.init(session: NetworkSession.shared)
    }

    /// Creates an engine with an externally provided URLSession.
     package init(session: URLSession) {
        self.session = session
    }

    /// Sends a GET request through URLSession.
    package func getJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        try await execute(
            url: request.url,
            method: "GET",
            headers: request.headers,
            body: request.body
        )
    }

    /// Sends a JSON POST request through URLSession.
    package func postJSON(_ request: ConsultantHTTPRequest) async throws -> ConsultantHTTPResponse {
        try await execute(
            url: request.url,
            method: "POST",
            headers: request.headers,
            body: request.body
        )
    }

    /// Sends a raw POST request through URLSession.
    package func postRaw(_ request: ConsultantRawHTTPRequest) async throws -> ConsultantHTTPResponse {
        try await execute(
            url: request.url,
            method: "POST",
            headers: request.headers,
            body: request.body,
            contentType: request.contentType
        )
    }

    private func execute(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?,
        contentType: String? = nil
    ) async throws -> ConsultantHTTPResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body

        if let contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await NetworkSession.data(
            for: urlRequest, in: session
        )
        let httpResponse = response as? HTTPURLResponse

        return ConsultantHTTPResponse(
            statusCode: httpResponse?.statusCode ?? 0,
            body: data
        )
    }
}
