import Foundation

/// File preview item opened by the SDK preview viewer.
package struct FilePreviewItem: Equatable {

    /// Backend file item identifier, if one is available.
    package let id: String?

    /// URL used by the preview viewer.
    package let url: URL

    /// File name displayed in the preview viewer.
    package let displayName: String

    /// Optional human-readable file size carried from the message bubble.
    package let sizeLabel: String?

    /// Preferred file extension used when a preview URL has no useful extension.
    package let preferredFileExtension: String?

    /// Creates a file preview item for remote, data, or local file URLs.
    package init(
        id: String?,
        url: URL,
        displayName: String,
        sizeLabel: String?,
        preferredFileExtension: String? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.preferredFileExtension = preferredFileExtension
    }

    /// Returns a copy pointing to a different URL while keeping display metadata.
    package func replacingURL(_ url: URL) -> FilePreviewItem {
        FilePreviewItem(
            id: id,
            url: url,
            displayName: displayName,
            sizeLabel: sizeLabel,
            preferredFileExtension: preferredFileExtension
        )
    }
}
