import CoreGraphics
import Foundation

/// UI-ready file or image item extracted from a consultant message.
package struct MessageFileDisplayItem: Equatable {

    /// Backend file item identifier, if one is available.
    package let id: String?

    /// File name or fallback title displayed in the bubble.
    package let displayName: String

    /// Human-readable file size displayed below the file name.
    package let sizeLabel: String?

    /// Remote, data, or local file URL string used for preview and loading.
    package let urlString: String?

    /// Optional original image size used by image-message layout.
    package let sourceImageSize: CGSize?

    /// Creates a placeholder display item when the message has no usable file item data.
    package static func fallback(displayName: String) -> MessageFileDisplayItem {
        MessageFileDisplayItem(
            id: nil,
            displayName: displayName,
            sizeLabel: nil,
            urlString: nil,
            sourceImageSize: nil
        )
    }

    package init(
        id: String?,
        displayName: String,
        sizeLabel: String?,
        urlString: String?,
        sourceImageSize: CGSize?
    ) {
        self.id = id
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.urlString = urlString
        self.sourceImageSize = sourceImageSize
    }
}
