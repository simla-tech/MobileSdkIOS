import Foundation

/// Observes SDK HTTP requests without changing their execution.
/// Callbacks run asynchronously on a private serial queue, outside SDK locks.
/// The SDK retains the observer. Implementations must support use across threads.
public protocol CrmSdkNetworkObserver: Sendable {
    func requestDidStart(_ event: CrmSdkNetworkRequest)
    func requestDidComplete(_ event: CrmSdkNetworkResponse)

    /// Enables URLSession task metrics. Disabled by default.
    var collectsMetrics: Bool { get }
    /// Metrics may arrive before or after completion. Correlate them using requestID.
    func requestDidCollectMetrics(_ metrics: URLSessionTaskMetrics, requestID: UUID)
}

public extension CrmSdkNetworkObserver {
    var collectsMetrics: Bool { false }
    func requestDidCollectMetrics(_ metrics: URLSessionTaskMetrics, requestID: UUID) {}
}

/// An HTTP request prepared by the SDK, including its configured request timeout.
/// Each execution, including a retry, receives a new identifier.
public struct CrmSdkNetworkRequest: Sendable {
    public let id: UUID
    public let request: URLRequest
    public let startedAt: Date
}

/// The transport result before HTTP status validation or response decoding.
public struct CrmSdkNetworkResponse: Sendable {
    public let id: UUID
    public let response: URLResponse?
    /// Response bytes for data tasks. Nil for file downloads or absent data.
    public let responseBody: Data?
    /// Transport error, including SDK timeout and cancellation errors.
    /// HTTP 4xx/5xx responses do not set this property by themselves.
    public let error: (any Error)?
    /// Elapsed seconds measured using a monotonic clock.
    public let duration: TimeInterval
}

/// Delivers transient events; it does not retain request history.
package final class NetworkObservationDelivery: @unchecked Sendable {
    private let observer: any CrmSdkNetworkObserver
    private let queue = DispatchQueue(label: "com.retailcrm.sdk.network-observer", qos: .utility)
    package let collectsMetrics: Bool

    package init(observer: any CrmSdkNetworkObserver) {
        self.observer = observer
        self.collectsMetrics = observer.collectsMetrics
    }

    package func begin(request: URLRequest) -> NetworkTaskObservation {
        let event = CrmSdkNetworkRequest(id: UUID(), request: request, startedAt: Date())
        let observation = NetworkTaskObservation(id: event.id, delivery: self)
        queue.async { [observer] in observer.requestDidStart(event) }
        return observation
    }

    fileprivate func complete(_ event: CrmSdkNetworkResponse) {
        queue.async { [observer] in observer.requestDidComplete(event) }
    }

    fileprivate func metrics(_ metrics: URLSessionTaskMetrics, requestID: UUID) {
        queue.async { [observer] in observer.requestDidCollectMetrics(metrics, requestID: requestID) }
    }
}

package final class NetworkTaskObservation: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let id: UUID
    private let delivery: NetworkObservationDelivery
    private let startedAt = ProcessInfo.processInfo.systemUptime

    fileprivate init(id: UUID, delivery: NetworkObservationDelivery) {
        self.id = id
        self.delivery = delivery
    }

    /// Task delegates are supported on iOS 15+ for foreground URL sessions.
    package func attachMetrics(to task: URLSessionTask, in session: URLSession) {
        guard delivery.collectsMetrics, session.configuration.identifier == nil else { return }
        task.delegate = self
    }

    package func finish(response: URLResponse?, data: Data?, error: Error?) {
        delivery.complete(CrmSdkNetworkResponse(
            id: id, response: response, responseBody: data, error: error,
            duration: max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        ))
    }

    package func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        delivery.metrics(metrics, requestID: id)
        // Preserve metrics handling installed by the application's session delegate.
        (session.delegate as? URLSessionTaskDelegate)?.urlSession?(
            session, task: task, didFinishCollecting: metrics
        )
    }
}
