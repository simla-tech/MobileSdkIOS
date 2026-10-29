import Foundation

/// Image preview item opened from an image message bubble.
package struct ImagePreviewItem: Equatable {

    /// Backend file item identifier, if one is available.
    package let id: String?

    /// Image URL used by the preview viewer.
    package let url: URL

    /// Optional caption used as the preview file name.
    package let caption: String?

    /// Converts this image preview into a generic file preview item.
    package func filePreviewItem(index: Int) -> FilePreviewItem {
        FilePreviewItem(
            id: id,
            url: url,
            displayName: normalizedPreviewDisplayName(index: index),
            sizeLabel: nil,
            preferredFileExtension: preferredPreviewFileExtension()
        )
    }

    /// Returns a user-facing file name for the preview viewer.
    private func normalizedPreviewDisplayName(index: Int) -> String {
        let normalizedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCaption, !normalizedCaption.isEmpty {
            return normalizedCaption
        }

        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastPathExtension = URL(fileURLWithPath: lastPathComponent).pathExtension.lowercased()
        if !lastPathComponent.isEmpty,
           lastPathComponent != "data",
           lastPathExtension != "data" {
            return lastPathComponent
        }

        return "photo-\(index + 1)"
    }

    /// Returns an image file extension suitable for generated preview file names.
    private func preferredPreviewFileExtension() -> String {
        let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.previewImageExtensions.contains(pathExtension) {
            return pathExtension
        }

        return "jpg"
    }

    /// Image file extensions preserved by the preview viewer.
    private static let previewImageExtensions: Set<String> = [
        "gif",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "png",
        "webp"
    ]

    package init(
        id: String?,
        url: URL,
        caption: String?
    ) {
        self.id = id
        self.url = url
        self.caption = caption
    }
}
