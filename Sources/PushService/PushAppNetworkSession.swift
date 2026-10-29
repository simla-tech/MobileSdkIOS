import Core
import Foundation
import PushNotificationExtension

/// Applies the application's SDK timeouts to push requests.
package struct PushAppNetworkSession: PushNetworkSession {
    private let session: URLSession

    package init(session: URLSession) {
        self.session = session
    }

    package func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        NetworkSession.dataTask(
            with: request, in: session,
            completionHandler: completionHandler
        )
    }

    package func downloadTask(
        with url: URL,
        completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask {
        NetworkSession.downloadTask(
            with: url, in: session,
            completionHandler: completionHandler
        )
    }
}
