import CoreGraphics
import Foundation

/// File or image item from backend `message.items`.
package struct MessageItem: Codable, Equatable, Sendable {

    /// Uploaded file identifier from backend `items[].id`.
    package let id: String?

    /// File caption from backend `items[].caption`.
    package let caption: String?

    /// File size in bytes from backend `items[].size`.
    package let size: Int64?

    /// Image width in pixels from backend `items[].width`.
    package let width: Double?

    /// Image height in pixels from backend `items[].height`.
    package let height: Double?

    /// File or image URL from backend `items[].url`.
    ///
    /// The SDK also fills this value locally after resolving a file link by `id`.
    package let url: String?

    /// Creates a typed file or image message item.
    package init(
        id: String? = nil,
        caption: String? = nil,
        size: Int64? = nil,
        width: Double? = nil,
        height: Double? = nil,
        url: String? = nil
    ) {
        self.id = id?.nilIfEmpty
        self.caption = caption?.nilIfEmpty
        self.size = size
        self.width = width
        self.height = height
        self.url = url?.nilIfEmpty
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeFlexibleStringIfPresent(forKey: .id)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)?.nilIfEmpty
        size = try container.decodeFlexibleInt64IfPresent(forKey: .size)
        width = try container.decodeFlexibleDoubleIfPresent(forKey: .width)
        height = try container.decodeFlexibleDoubleIfPresent(forKey: .height)
        url = try container.decodeIfPresent(String.self, forKey: .url)?.nilIfEmpty
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(url, forKey: .url)
    }

    private enum CodingKeys: String, CodingKey {

        case id
        case caption
        case size
        case width
        case height
        case url
    }
}

package extension MessageItem {

    var resolvedFileURL: String? {
        url
    }

    var sourceImageSize: CGSize? {
        guard
            let width,
            let height,
            width > 0,
            height > 0
        else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    var displayFileName: String? {
        caption ?? id
    }

    var fileSizeLabel: String? {
        guard let size else {
            return nil
        }

        return Self.formattedFileSize(size)
    }

    func applyingFileLink(_ url: String) -> MessageItem {
        .init(
            id: id,
            caption: caption,
            size: size,
            width: width,
            height: height,
            url: url
        )
    }

    func preservingResolvedFileLink(from existing: MessageItem) -> MessageItem {
        .init(
            id: id,
            caption: caption ?? existing.caption,
            size: size ?? existing.size,
            width: width ?? existing.width,
            height: height ?? existing.height,
            url: url ?? existing.url
        )
    }

    private static func formattedFileSize(_ bytes: Int64) -> String {
        guard bytes >= 0 else {
            return "0 B"
        }

        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        if unitIndex == 0 || value >= 10 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

private extension KeyedDecodingContainer {

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value.nilIfEmpty
        }

        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }

        if let value = try decodeIfPresent(Double.self, forKey: key) {
            guard value.isFinite else {
                return nil
            }

            if value.rounded() == value {
                return String(Int64(value))
            }

            return String(value)
        }

        return nil
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Double.self, forKey: key) {
            guard value.isFinite else {
                return nil
            }

            return Int64(value)
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }
}
