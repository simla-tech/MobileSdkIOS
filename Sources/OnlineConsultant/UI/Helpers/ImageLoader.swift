import Core
import UIKit

/// Cancellable task returned by the SDK image loader.
package protocol ImageLoadTask {

    /// Cancels the underlying image loading operation.
    func cancel()
}

extension URLSessionDataTask: ImageLoadTask {}

/// Loads and caches images used by message bubbles, avatars, and previews.
package final class ImageLoader {

    /// Shared image loader used by SDK UI components.
    package static let shared = ImageLoader()

    private let session: URLSession
    private let cache: NSCache<NSURL, UIImage>

    /// Creates an image loader with injectable networking and cache dependencies for tests.
    package init(
        session: URLSession = NetworkSession.shared,
        cache: NSCache<NSURL, UIImage> = NSCache<NSURL, UIImage>()
    ) {
        self.session = session
        self.cache = cache
    }

    /// Returns a cached image for the URL, if it has already been loaded.
    package func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Loads an image from memory cache, data URL, file URL, or network URL.
    ///
    /// The completion is called synchronously for cache, data URL, and file URL hits.
    /// Network results are delivered on the main queue.
    @discardableResult
    package func loadImage(
        from url: URL,
        completion: @escaping (UIImage?) -> Void
    ) -> ImageLoadTask? {
        if let cachedImage = cachedImage(for: url) {
            completion(cachedImage)
            return nil
        }

        if let data = Self.imageData(from: url.absoluteString) {
            let image = UIImage(data: data)
            cache(image, for: url)
            completion(image)
            return nil
        }

        if url.isFileURL {
            let image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            cache(image, for: url)
            completion(image)
            return nil
        }

        let task = NetworkSession.dataTask(
            with: URLRequest(url: url), in: session
        ) { [weak self] data, _, _ in
            guard
                let data,
                let image = UIImage(data: data)
            else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            self?.cache(image, for: url)

            DispatchQueue.main.async {
                completion(image)
            }
        }
        task.resume()
        return task
    }

    /// Stores an image in memory cache using an approximate RGBA bitmap cost.
    private func cache(_ image: UIImage?, for url: URL) {
        guard let image else {
            return
        }

        let pixelWidth = max(1, Int(image.size.width * image.scale))
        let pixelHeight = max(1, Int(image.size.height * image.scale))
        cache.setObject(
            image,
            forKey: url as NSURL,
            cost: pixelWidth * pixelHeight * 4
        )
    }

    /// Decodes base64 data from a `data:image/...;base64,...` URL string.
    private static func imageData(from value: String) -> Data? {
        guard value.hasPrefix("data:image/") else {
            return nil
        }

        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            parts[0].contains(";base64")
        else {
            return nil
        }

        return Data(base64Encoded: String(parts[1]))
    }
}
