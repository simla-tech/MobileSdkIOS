import UIKit
import XCTest
@testable import OnlineConsultant

final class ConsultantImageLoaderTests: XCTestCase {

    override func tearDown() {
        ImageLoaderURLProtocol.reset()
        super.tearDown()
    }

    func testLoadImageUsesMemoryCacheForRepeatedURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/image.png"))
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ImageLoaderURLProtocol.self]
        let loader = ImageLoader(
            session: URLSession(configuration: sessionConfiguration)
        )
        ImageLoaderURLProtocol.responseData = try XCTUnwrap(Self.makeImageData())

        let firstImage = await loadImage(from: url, using: loader)
        let secondImage = await loadImage(from: url, using: loader)

        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(ImageLoaderURLProtocol.requestCount, 1)
    }

    func testLoadImageReadsLocalSourcesAndCachesResult() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ImageLoaderTests-\(UUID().uuidString).png")
        try XCTUnwrap(Self.makeImageData()).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let dataURL = try XCTUnwrap(URL(string: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/l8dKWAAAAABJRU5ErkJggg=="))
        for url in [fileURL, dataURL] {
            let loader = ImageLoader()
            let first = await loadImage(from: url, using: loader)
            let second = await loadImage(from: url, using: loader)
            XCTAssertNotNil(first, url.scheme ?? "")
            XCTAssertNotNil(second, url.scheme ?? "")
            XCTAssertNotNil(loader.cachedImage(for: url), url.scheme ?? "")
        }
    }

    private func loadImage(
        from url: URL,
        using loader: ImageLoader
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loader.loadImage(from: url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private static func makeImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.pngData()
    }
}

private final class ImageLoaderURLProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var currentRequestCount = 0

    static var responseData: Data?

    static var requestCount: Int {
        lock.withLock { currentRequestCount }
    }

    static func reset() {
        lock.withLock {
            currentRequestCount = 0
            responseData = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.currentRequestCount += 1
        }

        let data = Self.responseData ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
