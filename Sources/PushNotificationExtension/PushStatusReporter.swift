import Foundation
import SDKConfiguration

package struct PushStatusReporter: Sendable {

    private let session: any PushNetworkSession
    private let retryQueue: PushStatusRetryQueue
    private let clientAPIEndpointURL: URL

    package init(
        session: any PushNetworkSession,
        retryQueue: PushStatusRetryQueue = .shared,
        clientAPIEndpointURL: URL = BackendEndpoints().clientAPIEndpointURL
    ) {
        self.session = session
        self.clientAPIEndpointURL = clientAPIEndpointURL
        self.retryQueue = retryQueue
        retryQueue.resume(using: session)
    }

    package func reportStatus(
        _ status: PushNotificationStatus,
        pushId: String,
        buttonHash: String? = nil,
        siteToken: String,
        completion: @escaping (Result<Void, PushStatusReportingError>) -> Void = { _ in }
    ) {
        let requestBody = PushStatusRequestBody(
            changedAt: Int64(Date().timeIntervalSince1970),
            pushId: pushId,
            status: status,
            buttonHash: buttonHash
        )

        Self.send(
            requestBody, siteToken: siteToken, clientAPIEndpointURL: clientAPIEndpointURL, session: session
        ) { result, retryAfter in
            if case .failure(let error) = result, error.isRetryable {
                retryQueue.enqueue(
                    requestBody, siteToken: siteToken, clientAPIEndpointURL: clientAPIEndpointURL,
                    retryAfter: retryAfter, error: error
                ) {
                    completion(result)
                }
            } else {
                retryQueue.discard(
                    requestBody, siteToken: siteToken, clientAPIEndpointURL: clientAPIEndpointURL, result: result
                ) { completion(result) }
            }
        }
    }

    /// Performs one attempt without changing the original event time or scheduling another request.
    package static func send(
        _ body: PushStatusRequestBody,
        siteToken: String,
        clientAPIEndpointURL: URL = BackendEndpoints().clientAPIEndpointURL,
        session: any PushNetworkSession,
        completion: @escaping (Result<Void, PushStatusReportingError>, TimeInterval?) -> Void
    ) {

        var request = URLRequest(
            url: clientAPIEndpointURL.appendingPathComponent("push-tokens/set-status")
        )
        request.httpMethod = "POST"
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(.requestEncodingFailed(error.localizedDescription)), nil)
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(siteToken, forHTTPHeaderField: "X-Site-Token")

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.requestFailed(error.localizedDescription)), nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidHTTPResponse(String(describing: response))), nil)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let responseData = data ?? Data()
                var messages = (try? JSONDecoder().decode(PushStatusErrorResponse.self, from: responseData))?.messages ?? []
                if messages.isEmpty,
                   let message = String(data: responseData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                    messages = [message]
                }
                completion(.failure(.httpStatus(httpResponse.statusCode, messages)), retryAfter(from: httpResponse))
                return
            }

            completion(.success(()), nil)
        }
        task.resume()
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}

package extension PushStatusReportingError {
    var isRetryable: Bool {
        switch self {
        case .requestFailed, .invalidHTTPResponse:
            return true
        case .httpStatus(let code, _):
            return code == 408 || code == 425 || code == 429 || (500..<600).contains(code)
        case .requestEncodingFailed:
            return false
        }
    }
}

private struct PushStatusErrorResponse: Decodable {
    let error: String?
    let errors: [String]?

    var messages: [String] {
        if let errors, !errors.isEmpty {
            return errors
        }

        if
            let error = error?.trimmingCharacters(in: .whitespacesAndNewlines),
            !error.isEmpty
        {
            return [error]
        }

        return []
    }
}
