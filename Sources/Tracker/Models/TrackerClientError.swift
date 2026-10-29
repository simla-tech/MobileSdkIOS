import Foundation

package enum TrackerClientError: Error, Equatable {
    case httpStatus(Int, Data, retryAfter: TimeInterval?)

    package var rateLimitRetryAfter: TimeInterval? {
        guard case let .httpStatus(statusCode, _, retryAfter) = self, statusCode == 429 else {
            return nil
        }

        return retryAfter
    }

    package var asTrackerError: TrackerError {
        switch self {
        case .httpStatus(0, _, _):
            return .invalidResponse(TrackerLocalization.missingHTTPResponse.localized)
        case let .httpStatus(status, data, retryAfter):
            let message = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: String] }?["error"]
            return .httpStatus(status, message.map { [$0] } ?? [], retryAfter: retryAfter)
        }
    }
}
