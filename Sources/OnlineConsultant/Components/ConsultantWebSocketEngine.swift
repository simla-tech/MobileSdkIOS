import Core
import Foundation

/// Component responsible for the SDK realtime WebSocket transport.
///
/// It builds WebSocket handshake requests, receives backend push payloads, and
/// exposes only message data that the client can decode into realtime events.
/// Opens the realtime WebSocket connection used by the online consultant client.
package protocol ConsultantWebSocketEngine: AnyObject {

    /// Opens a WebSocket request and emits received backend message payloads.
    func open(_ request: ConsultantWebSocketRequest) -> AsyncThrowingStream<ConsultantWebSocketEvent, Error>
}

/// Describes a WebSocket connection request.
package struct ConsultantWebSocketRequest: Equatable, Sendable {

    /// WebSocket endpoint URL with query parameters.
     package let url: URL
    /// HTTP headers applied during the WebSocket handshake.
     package let headers: [String: String]

    /// Creates a WebSocket request descriptor.
     package init(
        url: URL,
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.headers = headers
    }
}

/// Event emitted by a WebSocket engine.
package enum ConsultantWebSocketEvent: Equatable, Sendable {

    /// Text message received from the backend.
    case event(rawText: String)
    /// Binary message received from the backend.
    case binary(Data)
}

/// URLSession-backed implementation of the consultant WebSocket engine.
package final class URLSessionConsultantWebSocketEngine: ConsultantWebSocketEngine {

    private let session: URLSession
    private let connectTimeout: TimeInterval

    /// Creates a WebSocket engine with an opening timeout applied to the handshake request.
     package init(
        session: URLSession = NetworkSession.shared,
        connectTimeout: TimeInterval = 30
    ) {
        self.session = session
        self.connectTimeout = connectTimeout
    }

    /// Opens the WebSocket and returns an async stream of received events.
     package func open(_ request: ConsultantWebSocketRequest) -> AsyncThrowingStream<ConsultantWebSocketEvent, Error> {
        AsyncThrowingStream { continuation in
            var preparedRequest = URLRequest(url: request.url)
            preparedRequest.timeoutInterval = connectTimeout

            request.headers.forEach { key, value in
                preparedRequest.setValue(value, forHTTPHeaderField: key)
            }
            let urlRequest = preparedRequest

            let task = session.webSocketTask(with: urlRequest)
            task.resume()

            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await receiveMessage(from: task)
                        continuation.yield(event(from: message))
                    }
                } catch {
                    guard !Task.isCancelled else { return }

                    if task.closeCode != .invalid {
                        continuation.finish()
                        return
                    }

                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func receiveMessage(
        from task: URLSessionWebSocketTask
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            task.receive { result in
                switch result {
                case .success(let message):
                    continuation.resume(returning: message)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func event(from message: URLSessionWebSocketTask.Message) -> ConsultantWebSocketEvent {
        switch message {
        case .string(let text):
            return .event(rawText: text)
        case .data(let data):
            return .binary(data)
        @unknown default:
            return .event(rawText: "")
        }
    }
}
