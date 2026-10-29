import Foundation

/// Builds product and image preview URLs using backend-provided image workers.
package enum ProductImagePreviewURL {

    /// Returns a resized worker URL when an image worker is available, otherwise the original image URL.
    package static func make(
        imageURLString: String?,
        imageWorkers: [String],
        resize: String = "160x160"
    ) -> URL? {
        guard let normalizedImageURLString = normalizedURLString(imageURLString) else {
            return nil
        }

        guard let worker = imageWorkers.compactMap(normalizedWorkerHost).first else {
            return URL(string: normalizedImageURLString)
        }

        return URL(string: "https://\(worker)/r/\(resize)/\(normalizedImageURLString)")
    }

    /// Normalizes and percent-encodes an image URL string for direct or worker loading.
    private static func normalizedURLString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let valueWithScheme = trimmedValue.hasPrefix("//")
            ? "https:\(trimmedValue)"
            : trimmedValue

        // Backend links may already contain escaped paths and signed query parameters.
        // Encoding '%' again changes their meaning and can invalidate the signature.
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.insert(charactersIn: "%")
        return valueWithScheme.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? valueWithScheme
    }

    /// Normalizes backend image worker values to host names accepted by the worker URL format.
    private static func normalizedWorkerHost(_ value: String) -> String? {
        var trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if trimmedValue.hasPrefix("https://") {
            trimmedValue.removeFirst("https://".count)
        } else if trimmedValue.hasPrefix("http://") {
            trimmedValue.removeFirst("http://".count)
        } else if trimmedValue.hasPrefix("//") {
            trimmedValue.removeFirst("//".count)
        }

        trimmedValue = trimmedValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
