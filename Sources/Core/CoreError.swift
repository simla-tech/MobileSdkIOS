import Foundation
import Security

/// Errors returned by Core operations.
public enum CoreError: Error, Equatable, LocalizedError, Sendable {

    /// Customer identity contains an empty or oversized value.
    case invalidCustomerIdentity(String)

    /// Connect response does not contain the user token or session id.
    case missingConnectionCredentials

    /// Backend returned a non-success HTTP status with response messages.
    case httpStatus(Int, [String])

    /// The saved user token is not valid UTF-8.
    case keychainInvalidTokenData

    /// A Keychain operation failed with the given OSStatus.
    case keychainUnexpectedStatus(Int32)

    /// Data could not be encoded.
    case requestEncodingFailed(String)

    /// Data could not be decoded.
    case responseDecodingFailed(String)

    /// The connect request failed before receiving a response.
    case requestFailed(String)

    /// The operation was cancelled.
    case cancelled

    /// An unexpected operation error occurred.
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCustomerIdentity(let message):
            return message
        case .missingConnectionCredentials:
            return CoreLocalization.sessionMissingCredentials.localized
        case .httpStatus(let statusCode, let messages):
            let description = CoreLocalization.sessionHTTPStatus.format(statusCode)
            return messages.isEmpty ? description : description + " " + messages.joined(separator: " ")
        case .keychainInvalidTokenData:
            return CoreLocalization.keychainInvalidTokenData.localized
        case .keychainUnexpectedStatus(let status):
            let description = CoreLocalization.keychainUnexpectedStatus.format(status)
            guard let message = SecCopyErrorMessageString(status, nil) as String?, !message.isEmpty else {
                return description
            }
            return description + " " + message
        case .requestEncodingFailed(let message):
            return CoreLocalization.requestEncodingFailed.format(message)
        case .responseDecodingFailed(let message):
            return CoreLocalization.responseDecodingFailed.format(message)
        case .requestFailed(let message):
            return CoreLocalization.requestFailed.format(message)
        case .cancelled:
            return CoreLocalization.cancelled.localized
        case .unexpected(let message):
            return CoreLocalization.unexpected.format(message)
        }
    }
}

package extension CoreError {

    static func wrapping(_ error: Error) -> Self {
        if let coreError = error as? Self {
            return coreError
        }
        if error is CancellationError {
            return .cancelled
        }
        if error is EncodingError {
            return .requestEncodingFailed(error.localizedDescription)
        }
        if error is DecodingError {
            return .responseDecodingFailed(error.localizedDescription)
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return .requestFailed(error.localizedDescription)
        }
        return .unexpected(error.localizedDescription)
    }
}

package extension CoreError {

    /// Extracts backend error messages from a raw HTTP response body.
    static func errorMessages(from data: Data) -> [String] {
        HTTPErrorResponseParser.messages(from: data, fallbackForEmptyMessages: false) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
                return nil
            }

            if let messages = object as? [String] {
                return messages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

            if let response = object as? [String: Any] {
                if let messages = response["errors"] as? [String] {
                    let nonemptyMessages = messages.filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    if !nonemptyMessages.isEmpty { return nonemptyMessages }
                }

                for key in ["errors", "error", "message"] {
                    if let message = response[key] as? String,
                       !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return [message]
                    }
                }
            }

            if let message = object as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [message]
            }

            return []
        }
    }
}

package enum HTTPErrorResponseParser {

    package static func messages(
        from data: Data,
        fallbackForEmptyMessages: Bool,
        parse: (Data) -> [String]?
    ) -> [String] {
        if let messages = parse(data), !messages.isEmpty || !fallbackForEmptyMessages {
            return messages
        }

        guard let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return []
        }
        return [message]
    }
}
