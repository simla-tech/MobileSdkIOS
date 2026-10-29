import Core
import Foundation

/// Component responsible for downloading remote message files into the local cache.
///
/// It loads remote file bytes, validates successful HTTP responses, preserves
/// response content type when available, and delegates disk persistence to
/// `ConsultantFileCache`.
/// Loads remote file content and stores it in the local SDK file cache.
package protocol ConsultantRemoteFileCacheLoading: AnyObject {
    /// Downloads a remote file and returns the local cached file URL.
    func cacheRemoteFile(
        fileID: String,
        remoteURL: URL
    ) async throws -> URL
}

/// Abstracts remote data loading for file-cache downloads.
package protocol ConsultantRemoteFileDataLoading: AnyObject {
    /// Loads data for a URL request.
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ConsultantRemoteFileDataLoading {

    /// Loads data using URLSession dataTask.
    package func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await NetworkSession.data(
            for: request, in: self
        )
        return (data, response)
    }
}

/// Default remote file cache loader used by the controller.
package final class RemoteFileCacheLoader: ConsultantRemoteFileCacheLoading {

    private let fileCache: ConsultantFileCache
    private let dataLoader: ConsultantRemoteFileDataLoading

    /// Creates a loader with a local file cache and remote data loader.
    package init(
        fileCache: ConsultantFileCache,
        dataLoader: ConsultantRemoteFileDataLoading = NetworkSession.shared
    ) {
        self.fileCache = fileCache
        self.dataLoader = dataLoader
    }

    /// Downloads a remote file, validates the HTTP response, and stores the bytes in the local cache.
    package func cacheRemoteFile(
        fileID: String,
        remoteURL: URL
    ) async throws -> URL {
        let (data, response) = try await dataLoader.loadData(for: URLRequest(url: remoteURL))

        if let httpResponse = response as? HTTPURLResponse,
           !httpResponse.isSuccessful
        {
            throw ConsultantClientError.httpStatus(httpResponse.statusCode, CoreError.errorMessages(from: data))
        }

        return try fileCache.store(
            data: data,
            fileID: fileID,
            contentType: response.contentType,
            remoteURL: remoteURL
        )
    }
}

private extension HTTPURLResponse {

    var isSuccessful: Bool {
        (200..<300).contains(statusCode)
    }
}

private extension URLResponse {

    var contentType: String? {
        (self as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? mimeType
    }
}
