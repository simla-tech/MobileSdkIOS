import Core
import Foundation

/// Internal client that maps SDK operations to backend HTTP endpoints and realtime WebSocket events.
package final class OnlineConsultantClient {

    /// Runtime configuration used to build backend requests.
    package let config: OnlineConsultantConfig

    private let sessionRuntime: SessionRuntime
    private let networkEngine: ConsultantNetworkEngine
    private let webSocketEngine: ConsultantWebSocketEngine
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Page size used when loading older messages.
    package var messagesPageSize: Int {
        max(1, min(config.messagesPageSize, 1_000))
    }

    /// Maximum number of messages loaded during initial connection bootstrap.
    package var initialMessagesLimit: Int {
        max(0, min(config.initialMessagesLimit, 1_000))
    }

    /// Creates a client with injectable networking and WebSocket dependencies.
    package init(
        config: OnlineConsultantConfig,
        sessionRuntime: SessionRuntime,
        networkEngine: ConsultantNetworkEngine? = nil,
        webSocketEngine: ConsultantWebSocketEngine? = nil
    ) {
        self.config = config
        self.sessionRuntime = sessionRuntime
        self.networkEngine = networkEngine ?? URLSessionConsultantNetworkEngine()
        self.webSocketEngine = webSocketEngine ?? URLSessionConsultantWebSocketEngine(
            connectTimeout: config.connectTimeout
        )
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
}

// MARK: - Connection

package extension OnlineConsultantClient {

    /// Whether the shared session has no customer identity.
    func isAnonymousSession() async -> Bool {
        await sessionRuntime.customerIdentity == nil
    }

    /// Opens or resumes a consultant session through the backend connect endpoint.
    func connect() async throws -> ConsultantConnectResponse {
        do {
            return try await sessionRuntime.connect(
                responseType: ConsultantConnectResponse.self
            )
        } catch {
            throw consultantClientError(from: error)
        }
    }

    private func consultantClientError(from error: Error) -> ConsultantClientError {
        if let error = error as? ConsultantClientError {
            return error
        }

        if let error = error as? CoreError {
            switch error {
            case .invalidCustomerIdentity(let message):
                return .requestFailed(message)
            case .missingConnectionCredentials:
                return .missingConnectionCredentials
            case .httpStatus(let statusCode, let messages):
                return .httpStatus(statusCode, messages)
            default:
                return .requestFailed(error.localizedDescription)
            }
        }

        return .requestFailed(error.localizedDescription)
    }
}

// MARK: - Realtime

package extension OnlineConsultantClient {

    /// Opens a WebSocket stream and decodes backend realtime events.
    func subscribeRealtimeEvents(
        session: String,
        userToken: String,
        updatedAt: String? = nil
    ) -> AsyncThrowingStream<ConsultantRealtimeEvent, Error> {
        let webSocketStream = webSocketEngine.open(
            ConsultantWebSocketRequest(
                url: webSocketURL(
                    session: session,
                    userToken: userToken,
                    updatedAt: updatedAt
                ),
                headers: [
                    "X-User-Token": userToken,
                    "X-Session-Id": session
                ]
            )
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Deduplication is disabled while duplicate WebSocket delivery is investigated.
                // var lastRealtimeEvent: ConsultantRealtimeEvent?

                do {
                    for try await event in webSocketStream {
                        guard !Task.isCancelled else { return }

                        if let realtimeEvent = try self.decodeRealtimeEvent(from: event) {
                            continuation.yield(realtimeEvent)
                        }
                    }

                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Messages

package extension OnlineConsultantClient {

    /// Sends a visitor text message to the backend.
    func sendMessage(
        _ text: String,
        session: String,
        userToken: String
    ) async throws -> ConsultantSentMessage {
        try await sendMessage(
            text: text,
            type: .text,
            items: [],
            session: session,
            userToken: userToken
        )
    }

    /// Sends a message body to the backend.
    func sendMessage(
        text: String?,
        type: MessageType,
        items: [ConsultantSendMessageItem],
        session: String,
        userToken: String
    ) async throws -> ConsultantSentMessage {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: endpointURL("messages"),
                headers: authorizedHeaders(session: session, userToken: userToken),
                body: try encoder.encode(
                    ConsultantSendMessageRequest(
                        message: ConsultantSendMessageBody(
                            type: type,
                            text: text,
                            items: items.isEmpty ? nil : items
                        )
                    )
                )
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }

        return try decode(ConsultantSendMessageResponse.self, from: response).message
    }

    /// Loads a page of messages for the current session.
    func loadMessages(
        session: String,
        userToken: String,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [ConsultantMessage] {
        let response = try await networkEngine.getJSON(
            ConsultantHTTPRequest(
                url: messagesURL(
                    limit: limit ?? messagesPageSize,
                    offset: offset
                ),
                headers: authorizedHeaders(session: session, userToken: userToken)
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }

        return try decode(ConsultantMessagesResponse.self, from: response).messages
    }

    /// Marks incoming messages up to the provided backend message id as read for the current user.
    func markMessageRead(
        messageID: String,
        session: String,
        userToken: String
    ) async throws {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: messageReadURL(messageID: messageID),
                headers: authorizedHeaders(session: session, userToken: userToken)
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }
    }
}

// MARK: - Contact Forms

package extension OnlineConsultantClient {

    /// Submits contact-form data for the current session or a site-action contact form.
    func sendContactForm(
        _ data: ContactFormSubmitData,
        session: String,
        userToken: String,
        actionID: String? = nil
    ) async throws {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: contactFormURL(actionID: actionID),
                headers: authorizedHeaders(session: session, userToken: userToken),
                body: try encoder.encode(ConsultantContactFormRequest(data: data))
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }
    }

    /// Submits offline-form data for the current session.
    func sendOfflineForm(
        _ data: ContactFormSubmitData,
        session: String,
        userToken: String
    ) async throws {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: endpointURL("offline/form"),
                headers: authorizedHeaders(session: session, userToken: userToken),
                body: try encoder.encode(ConsultantContactFormRequest(data: data))
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }
    }
}

// MARK: - Actions

package extension OnlineConsultantClient {

    /// Executes a site action and returns its backend execution result.
    func executeAction(
        actionID: String,
        session: String,
        userToken: String
    ) async throws -> ConsultantActionExecuteResponse {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: actionExecuteURL(actionID: actionID),
                headers: authorizedHeaders(session: session, userToken: userToken)
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }

        return try decode(ConsultantActionExecuteResponse.self, from: response)
    }

    /// Reports that a site action was shown to the visitor.
    func showAction(
        actionID: String,
        session: String,
        userToken: String
    ) async throws {
        let response = try await networkEngine.postJSON(
            ConsultantHTTPRequest(
                url: actionShowURL(actionID: actionID),
                headers: authorizedHeaders(session: session, userToken: userToken)
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }
    }
}

// MARK: - Files

package extension OnlineConsultantClient {

    /// Loads a temporary URL for a backend file id.
    func loadFileLink(
        fileID: String,
        session: String,
        userToken: String
    ) async throws -> ConsultantFileLinkResponse {
        let response = try await networkEngine.getJSON(
            ConsultantHTTPRequest(
                url: fileLinkURL(fileID: fileID),
                headers: authorizedHeaders(session: session, userToken: userToken)
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }

        return try decode(ConsultantFileLinkResponse.self, from: response)
    }

    /// Uploads raw file data to the backend.
    func uploadFile(
        data: Data,
        contentType: String = "application/octet-stream",
        session: String,
        userToken: String
    ) async throws -> ConsultantFileUploadResponse {
        let response = try await networkEngine.postRaw(
            ConsultantRawHTTPRequest(
                url: endpointURL("files"),
                headers: rawAuthorizedHeaders(session: session, userToken: userToken),
                body: data,
                contentType: contentType
            )
        )

        guard response.isSuccessful else {
            throw ConsultantClientError.fromHTTP(statusCode: response.statusCode, body: response.body)
        }

        return try decode(ConsultantFileUploadResponse.self, from: response)
    }
}

// MARK: - Helpers

private extension OnlineConsultantClient {

    func decode<Value: Decodable>(
        _ type: Value.Type,
        from response: ConsultantHTTPResponse
    ) throws -> Value {
        return try decoder.decode(type, from: response.body)
    }

    func endpointURL(_ path: String) -> URL {
        path
            .split(separator: "/")
            .reduce(sessionRuntime.config.endpoints.clientAPIEndpointURL) { url, pathComponent in
                url.appendingPathComponent(String(pathComponent))
            }
    }

    func decodeRealtimeEvent(
        from webSocketEvent: ConsultantWebSocketEvent
    ) throws -> ConsultantRealtimeEvent? {
        switch webSocketEvent {
        case .event(let rawText):
            return try ConsultantRealtimeEvent(rawText: rawText)
        case .binary(let data):
            return try decoder.decode(ConsultantRealtimeEvent.self, from: data)
        }
    }

    func authorizedHeaders(session: String, userToken: String) -> [String: String] {
        var headers = sessionRuntime.siteHeaders(contentType: true)
        headers["X-User-Token"] = userToken
        headers["X-Session-Id"] = session
        return headers
    }

    func rawAuthorizedHeaders(session: String, userToken: String) -> [String: String] {
        var headers = sessionRuntime.siteHeaders(contentType: false)
        headers["X-User-Token"] = userToken
        headers["X-Session-Id"] = session
        return headers
    }

    func webSocketURL(
        session: String,
        userToken: String,
        updatedAt: String?
    ) -> URL {
        var components = URLComponents(
            url: sessionRuntime.config.endpoints.clientWebSocketEndpointURL,
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = realtimeQueryItems(
            session: session,
            userToken: userToken,
            updatedAt: updatedAt
        )

        return components.url!
    }

    func fileLinkURL(fileID: String) -> URL {
        sessionRuntime.config.endpoints.clientAPIEndpointURL
            .appendingPathComponent("files")
            .appendingPathComponent(fileID)
    }

    func actionExecuteURL(actionID: String) -> URL {
        sessionRuntime.config.endpoints.clientAPIEndpointURL
            .appendingPathComponent("actions")
            .appendingPathComponent(actionID)
            .appendingPathComponent("execute")
    }

    func actionShowURL(actionID: String) -> URL {
        sessionRuntime.config.endpoints.clientAPIEndpointURL
            .appendingPathComponent("actions")
            .appendingPathComponent(actionID)
            .appendingPathComponent("show")
    }

    func contactFormURL(actionID: String?) -> URL {
        let url = endpointURL("contact/form")
        guard let actionID = actionID?.nilIfEmpty else {
            return url
        }

        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "action_id", value: actionID)
        ]
        return components.url!
    }

    func messagesURL(
        limit: Int,
        offset: Int
    ) -> URL {
        var components = URLComponents(
            url: endpointURL("messages"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 1_000)))),
            URLQueryItem(name: "Offset", value: String(max(0, offset)))
        ]

        return components.url!
    }

    func messageReadURL(messageID: String) -> URL {
        sessionRuntime.config.endpoints.clientAPIEndpointURL
            .appendingPathComponent("messages")
            .appendingPathComponent(messageID)
            .appendingPathComponent("read")
    }

    func realtimeQueryItems(
        session: String,
        userToken: String,
        updatedAt: String?
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "token", value: userToken),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "updated_at", value: updatedAt ?? "undefined")
        ]
    }
}

/// Error returned by SDK network operations.
package enum ConsultantClientError: Error, Equatable, LocalizedError {

    /// Connect response does not contain required user token or session id.
    case missingConnectionCredentials

    /// Backend returned a non-success HTTP status with response messages.
    case httpStatus(Int, [String])

    /// Request, encoding, or decoding failed before a typed backend response could be returned.
    case requestFailed(String)

    package var errorDescription: String? {
        switch self {
        case .missingConnectionCredentials:
            return ConsultantLocalization.clientErrorMissingCredentials.localized
        case .httpStatus(let statusCode, let messages):
            let description = ConsultantLocalization.clientErrorHTTPStatus.format(statusCode)
            return messages.isEmpty ? description : description + " " + messages.joined(separator: " ")
        case .requestFailed(let message):
            return ConsultantLocalization.clientErrorRequestFailed.format(message)
        }
    }
}

private extension ConsultantClientError {
    static func fromHTTP(statusCode: Int, body: Data) -> Self {
        .httpStatus(statusCode, CoreError.errorMessages(from: body))
    }
}
