import Foundation
import SDKConfiguration

/// Observes the extension's requests without changing its timeouts or retry queue.
package struct ObservedPushNetworkSession: PushNetworkSession {
    let session: any PushNetworkSession
    let delivery: NetworkObservationDelivery

    init(session: any PushNetworkSession, observer: any CrmSdkNetworkObserver) {
        self.session = session
        self.delivery = NetworkObservationDelivery(observer: observer)
    }

    package func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let observation = delivery.begin(request: request)
        let task = session.dataTask(with: request) { data, response, error in
            observation.finish(response: response, data: data, error: error)
            completionHandler(data, response, error)
        }
        if let session = session as? URLSession { observation.attachMetrics(to: task, in: session) }
        return task
    }

    package func downloadTask(
        with url: URL,
        completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask {
        let observation = delivery.begin(request: URLRequest(url: url))
        let task = session.downloadTask(with: url) { url, response, error in
            observation.finish(response: response, data: nil, error: error)
            completionHandler(url, response, error)
        }
        if let session = session as? URLSession { observation.attachMetrics(to: task, in: session) }
        return task
    }
}
