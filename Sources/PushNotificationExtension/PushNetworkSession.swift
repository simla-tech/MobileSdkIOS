import Foundation

/// Network operations shared by notification enrichment and status reporting.
package protocol PushNetworkSession: Sendable {
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask

    func downloadTask(
        with url: URL,
        completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask
}

extension URLSession: PushNetworkSession {}
