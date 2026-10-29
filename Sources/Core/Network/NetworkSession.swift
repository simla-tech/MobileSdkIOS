import Foundation
import SDKConfiguration

/// The SDK's process-wide URL session and HTTP timeout policy.
package enum NetworkSession {
    private static let lock = NSLock()
    private static var requestTimeout: TimeInterval = 30
    private static var resourceTimeout: TimeInterval = 60
    private static var observationDelivery: NetworkObservationDelivery?

    /// WebSocket tasks share this session. Its resource timeout stays at the system default
    /// so an open WebSocket is not closed by the shorter HTTP deadline.
    package static let shared = URLSession(configuration: .default)

    package static func configure(
        requestTimeout: TimeInterval, resourceTimeout: TimeInterval,
        observer: (any CrmSdkNetworkObserver)? = nil
    ) {
        let delivery = observer.map { NetworkObservationDelivery(observer: $0) }
        lock.lock()
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.observationDelivery = delivery
        lock.unlock()
    }

    package static func data(
        for request: URLRequest,
        in session: URLSession = shared
    ) async throws -> (Data, URLResponse) {
        let cancellation = NetworkTaskCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = dataTask(
                    with: request, in: session
                ) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                cancellation.set(task)
                task.resume()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    package static func dataTask(
        with request: URLRequest,
        in session: URLSession = shared,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let (request, timeout, delivery) = prepared(request)
        let observation = delivery?.begin(request: request)
        let deadline = NetworkTaskDeadline()
        let task = session.dataTask(with: request) { data, response, error in
            let timedOut = deadline.cancel()
            let finalError = timedOut ? URLError(.timedOut)
                : (error ?? (response == nil ? URLError(.badServerResponse) : nil))
            observation?.finish(response: response, data: data, error: finalError)
            completionHandler(data, response, finalError)
        }
        observation?.attachMetrics(to: task, in: session)
        deadline.schedule(task: task, after: timeout)
        return task
    }

    package static func downloadTask(
        with url: URL,
        in session: URLSession = shared,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask {
        let (request, timeout, delivery) = prepared(URLRequest(url: url))
        let observation = delivery?.begin(request: request)
        let deadline = NetworkTaskDeadline()
        let task = session.downloadTask(with: request) { url, response, error in
            let timedOut = deadline.cancel()
            let finalError = timedOut ? URLError(.timedOut)
                : (error ?? (response == nil ? URLError(.badServerResponse) : nil))
            observation?.finish(response: response, data: nil, error: finalError)
            completionHandler(url, response, finalError)
        }
        observation?.attachMetrics(to: task, in: session)
        deadline.schedule(task: task, after: timeout)
        return task
    }

    private static func prepared(_ request: URLRequest) -> (URLRequest, TimeInterval, NetworkObservationDelivery?) {
        lock.lock()
        let requestTimeout = self.requestTimeout
        let resourceTimeout = self.resourceTimeout
        let delivery = self.observationDelivery
        lock.unlock()

        var request = request
        request.timeoutInterval = requestTimeout
        return (request, resourceTimeout, delivery)
    }
}

private final class NetworkTaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let isCancelled = self.isCancelled
        lock.unlock()
        if isCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

private final class NetworkTaskDeadline {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var timedOut = false

    func schedule(task: URLSessionTask, after interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + max(0, interval))
        timer.setEventHandler { [weak self, weak task] in
            guard let self else { return }
            self.lock.lock()
            let isActive = self.timer != nil
            if isActive { self.timedOut = true }
            self.lock.unlock()
            if isActive { task?.cancel() }
        }
        lock.lock()
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func cancel() -> Bool {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        let timedOut = self.timedOut
        lock.unlock()
        timer?.cancel()
        return timedOut
    }
}
