import Foundation
import UniformTypeIdentifiers

/// Builds stable upload metadata for images selected from `PHPickerViewController`.
package enum ImagePickerMetadata {

    /// Media type identifier used when configuring camera capture for still images.
    package static var imageMediaTypeIdentifier: String {
        UTType.image.identifier
    }

    /// File metadata needed to create and upload an input image attachment.
    package struct Metadata {
        /// Type identifier used to request binary data from `NSItemProvider`.
        package let typeIdentifier: String

        /// File name sent to the upload endpoint.
        package let fileName: String

        /// MIME type sent to the upload endpoint.
        package let contentType: String

        package init(
            typeIdentifier: String,
            fileName: String,
            contentType: String
        ) {
            self.typeIdentifier = typeIdentifier
            self.fileName = fileName
            self.contentType = contentType
        }
    }

    /// Creates upload metadata from the item provider exposed by the system photo picker.
    package static func make(from itemProvider: NSItemProvider) -> Metadata {
        let typeIdentifier = preferredImageTypeIdentifier(from: itemProvider)
        return Metadata(
            typeIdentifier: typeIdentifier,
            fileName: imageFileName(
                suggestedName: itemProvider.suggestedName,
                typeIdentifier: typeIdentifier
            ),
            contentType: imageContentType(for: typeIdentifier)
        )
    }

    private static let supportedTypeIdentifiers = [
        "public.jpeg",
        "public.png",
        "public.heic",
        "public.heif",
        "com.compuserve.gif",
        "public.tiff",
        "public.image"
    ]

    /// Selects the most specific supported image type identifier available on the item provider.
    private static func preferredImageTypeIdentifier(from itemProvider: NSItemProvider) -> String {
        supportedTypeIdentifiers.first { itemProvider.hasItemConformingToTypeIdentifier($0) }
            ?? "public.image"
    }

    /// Builds a file name from the provider suggestion and appends an extension when it is missing.
    private static func imageFileName(
        suggestedName: String?,
        typeIdentifier: String
    ) -> String {
        let fileExtension = imageFileExtension(for: typeIdentifier)
        let fallbackName = "photo-\(UUID().uuidString)"
        let trimmedSuggestedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseName: String
        if let trimmedSuggestedName, !trimmedSuggestedName.isEmpty {
            normalizedBaseName = trimmedSuggestedName
        } else {
            normalizedBaseName = fallbackName
        }
        let currentExtension = (normalizedBaseName as NSString).pathExtension

        guard currentExtension.isEmpty else {
            return normalizedBaseName
        }

        return "\(normalizedBaseName).\(fileExtension)"
    }

    /// Maps a Uniform Type Identifier to the file extension used in the upload file name.
    private static func imageFileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case "public.png":
            return "png"
        case "public.heic":
            return "heic"
        case "public.heif":
            return "heif"
        case "com.compuserve.gif":
            return "gif"
        case "public.tiff":
            return "tiff"
        default:
            return "jpg"
        }
    }

    /// Maps a Uniform Type Identifier to the MIME type sent with the upload request.
    private static func imageContentType(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case "public.png":
            return "image/png"
        case "public.heic":
            return "image/heic"
        case "public.heif":
            return "image/heif"
        case "com.compuserve.gif":
            return "image/gif"
        case "public.tiff":
            return "image/tiff"
        default:
            return "image/jpeg"
        }
    }
}
