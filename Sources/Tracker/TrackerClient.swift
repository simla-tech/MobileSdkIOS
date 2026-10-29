import Core
import Foundation

package final class TrackerClient {
    private let sessionRuntime: SessionRuntime
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    package init(sessionRuntime: SessionRuntime, session: URLSession = NetworkSession.shared) {
        self.sessionRuntime = sessionRuntime
        self.session = session
    }

    @discardableResult
    package func send(
        events: [TrackerEvent],
        expectedUserToken: String,
        onSending: ((String) -> Void)? = nil
    ) async throws -> TrackerStoreEventsResponse {
        guard !events.isEmpty else {
            return TrackerStoreEventsResponse()
        }

        guard let credentials = await sessionRuntime.credentials else {
            throw TrackerError.missingConnection
        }
        guard credentials.userToken == expectedUserToken else {
            throw TrackerError.missingConnection
        }

        let headers: [String: String]
        do {
            headers = try await sessionRuntime.authorizedHeaders()
        } catch {
            throw TrackerError.missingConnection
        }
        guard headers["X-User-Token"] == expectedUserToken else {
            throw TrackerError.missingConnection
        }

        var request = URLRequest(url: collectorEndpointURL(path: "event", credentials: credentials))
        request.httpMethod = "POST"
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let body: Data
        do {
            body = try encoder.encode(events)
        } catch {
            throw TrackerError.requestEncodingFailed(error.localizedDescription)
        }

        request.httpBody = body
        onSending?(String(decoding: body, as: UTF8.self))
        let (data, response) = try await NetworkSession.data(
            for: request, in: session
        )
        try Self.validateResponse(response, data: data)

        guard !data.isEmpty else {
            return TrackerStoreEventsResponse()
        }

        do {
            return try decoder.decode(TrackerStoreEventsResponse.self, from: data)
        } catch {
            throw TrackerError.invalidResponse(error.localizedDescription)
        }
    }

    package func fetchServerTime() async throws -> String? {
        guard let credentials = await sessionRuntime.credentials else {
            throw CoreError.missingConnectionCredentials
        }

        var request = URLRequest(url: collectorEndpointURL(path: "ts", credentials: credentials))
        request.httpMethod = "GET"
        for (header, value) in try await sessionRuntime.authorizedHeaders(contentType: false) {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await NetworkSession.data(
            for: request, in: session
        )
        try Self.validateResponse(response, data: data)

        guard !data.isEmpty else {
            return nil
        }

        do {
            return try decoder.decode(TrackerServerTimeResponse.self, from: data).timestamp
        } catch {
            throw TrackerError.invalidResponse(error.localizedDescription)
        }
    }

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackerClientError.httpStatus(0, data, retryAfter: nil)
        }

        let statusCode = httpResponse.statusCode
        guard (200..<300).contains(statusCode) else {
            throw TrackerClientError.httpStatus(
                statusCode,
                data,
                retryAfter: statusCode == 429
                    ? TrackerRateLimit.retryAfter(from: httpResponse, data: data)
                    : nil
            )
        }
    }

    private func collectorEndpointURL(path: String, credentials: SessionCredentials) -> URL {
        var components = URLComponents(
            url: sessionRuntime.config.endpoints.clientAPIEndpointURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "user", value: credentials.userToken),
            URLQueryItem(name: "session", value: credentials.sessionID)
        ]
        return components.url!
    }
}
