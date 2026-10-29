import XCTest
@testable import OnlineConsultant

final class RemoteFileCacheLoaderTests: XCTestCase {

    func testCacheRemoteFileDownloadsAndStoresFile() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteFileCacheLoaderTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: cacheRoot) }

        let remoteURL = URL(string: "https://example.test/photo.png")!
        let data = Data("image-data".utf8)
        let dataLoader = RemoteFileDataLoader(
            result: .success(
                (
                    data,
                    HTTPURLResponse(
                        url: remoteURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "image/png"]
                    )!
                )
            )
        )
        let fileCache = ConsultantFileCache(rootDirectory: cacheRoot)
        let loader = RemoteFileCacheLoader(
            fileCache: fileCache,
            dataLoader: dataLoader
        )

        let localURL = try await loader.cacheRemoteFile(
            fileID: "file-1",
            remoteURL: remoteURL
        )
        let entry = try XCTUnwrap(fileCache.entry(fileID: "file-1"))

        XCTAssertEqual(dataLoader.requests.map(\.url), [remoteURL])
        XCTAssertEqual(try Data(contentsOf: localURL), data)
        XCTAssertEqual(fileCache.cachedFileURL(fileID: "file-1"), localURL)
        XCTAssertEqual(entry.remoteURL, remoteURL)
        XCTAssertEqual(entry.contentType, "image/png")
        XCTAssertEqual(entry.size, Int64(data.count))
    }

    func testHTTPFailuresPreserveStatusAndMessageWithoutCachingResponse() async throws {
        for (status, body, message) in [(403, #"{"error":"Link expired"}"#, "Link expired"), (404, "not-found", "not-found")] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let url = try XCTUnwrap(URL(string: "https://example.test/photo.png"))
            let cache = ConsultantFileCache(rootDirectory: root)
            let loader = RemoteFileCacheLoader(fileCache: cache, dataLoader: RemoteFileDataLoader(result: .success((
                Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            ))))
            do {
                _ = try await loader.cacheRemoteFile(fileID: "file", remoteURL: url)
                XCTFail("Expected HTTP \(status)")
            } catch {
                XCTAssertEqual(error as? ConsultantClientError, .httpStatus(status, [message]), "HTTP \(status)")
                XCTAssertEqual(ConsultantError.from(error), .client(.httpStatus(status, [message])), "HTTP \(status)")
            }
            XCTAssertNil(cache.cachedFileURL(fileID: "file"), "HTTP \(status)")
            XCTAssertEqual(cache.statistics().fileCount, 0, "HTTP \(status)")
        }
    }

}

private final class RemoteFileDataLoader: ConsultantRemoteFileDataLoading {

    private let queue = DispatchQueue(label: "OnlineConsultantTests.RemoteFileDataLoader")
    private let result: Result<(Data, URLResponse), Error>
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        queue.sync {
            recordedRequests
        }
    }

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        queue.sync {
            recordedRequests.append(request)
        }

        return try result.get()
    }
}
