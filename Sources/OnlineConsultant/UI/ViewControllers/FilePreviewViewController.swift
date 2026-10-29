import QuickLook
import UIKit

/// QuickLook-backed viewer for file and image attachments opened from chat messages.
package final class FilePreviewViewController: QLPreviewController {

    private let quickLookItems: [FileQuickLookItem]
    private let initialPreviewItemIndex: Int
    private let temporaryPreviewDirectory: URL?

    /// Root directory used for temporary QuickLook copies.
    private static var temporaryPreviewRootDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlineConsultant", isDirectory: true)
            .appendingPathComponent("FilePreview", isDirectory: true)
    }

    package init(
        items: [FilePreviewItem],
        startIndex: Int
    ) {
        Self.removeStaleTemporaryPreviewDirectories()
        let preparedItems = Self.makeQuickLookItems(from: items)
        let quickLookItems = preparedItems.items
        self.quickLookItems = quickLookItems
        temporaryPreviewDirectory = preparedItems.temporaryDirectory
        initialPreviewItemIndex = Self.clampedIndex(
            startIndex,
            itemCount: quickLookItems.count
        )
        super.init(nibName: nil, bundle: nil)
        dataSource = self
        currentPreviewItemIndex = initialPreviewItemIndex
    }

    /// Storyboard initialization is not supported for the SDK preview controller.
    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let temporaryPreviewDirectory {
            try? FileManager.default.removeItem(at: temporaryPreviewDirectory)
        }
    }

    /// Clamps a requested preview index into the available item range.
    private static func clampedIndex(
        _ index: Int,
        itemCount: Int
    ) -> Int {
        guard itemCount > 0 else {
            return 0
        }

        return min(max(index, 0), itemCount - 1)
    }

    /// Converts SDK preview models into QuickLook items and tracks temporary local copies.
    private static func makeQuickLookItems(
        from items: [FilePreviewItem]
    ) -> (items: [FileQuickLookItem], temporaryDirectory: URL?) {
        let temporaryDirectory = temporaryPreviewRootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var didCreateTemporaryFile = false

        let quickLookItems = items.map { item in
            let preparedPreview = preparedPreviewURL(
                for: item,
                temporaryDirectory: temporaryDirectory
            )
            didCreateTemporaryFile = didCreateTemporaryFile || preparedPreview.didCreateTemporaryFile

            return FileQuickLookItem(
                item: item,
                previewURL: preparedPreview.url
            )
        }

        return (
            quickLookItems,
            didCreateTemporaryFile ? temporaryDirectory : nil
        )
    }

    /// Returns a QuickLook-safe URL for an item, copying local files to temporary names when needed.
    private static func preparedPreviewURL(
        for item: FilePreviewItem,
        temporaryDirectory: URL
    ) -> (url: URL, didCreateTemporaryFile: Bool) {
        guard item.url.isFileURL else {
            return (item.url, false)
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: item.url.path) else {
            return (item.url, false)
        }

        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let previewURL = temporaryDirectory.appendingPathComponent(
                previewFileName(for: item)
            )
            if fileManager.fileExists(atPath: previewURL.path) {
                try fileManager.removeItem(at: previewURL)
            }
            try fileManager.copyItem(at: item.url, to: previewURL)
            return (previewURL, true)
        } catch {
            return (item.url, false)
        }
    }

    /// Removes stale temporary preview directories left by previous preview sessions.
    package static func removeStaleTemporaryPreviewDirectories(
        now: Date = Date(),
        maxAge: TimeInterval = 24 * 60 * 60
    ) {
        let fileManager = FileManager.default
        let rootDirectory = temporaryPreviewRootDirectory

        guard
            let items = try? fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        items.forEach { itemURL in
            guard
                let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                values.isDirectory == true,
                let modificationDate = values.contentModificationDate,
                now.timeIntervalSince(modificationDate) > maxAge
            else {
                return
            }

            try? fileManager.removeItem(at: itemURL)
        }
    }

    /// Builds a sanitized file name for a temporary QuickLook copy.
    private static func previewFileName(for item: FilePreviewItem) -> String {
        let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = item.url.lastPathComponent.isEmpty ? "file" : item.url.lastPathComponent
        let rawFileName = displayName.isEmpty ? fallbackName : displayName
        let sanitizedFileName = rawFileName
            .map { character in
                Self.invalidFileNameCharacters.contains(character) ? "_" : character
            }
        let fileName = String(sanitizedFileName).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFileName = fileName.isEmpty ? "file" : fileName

        guard URL(fileURLWithPath: normalizedFileName).pathExtension.isEmpty else {
            return normalizedFileName
        }

        if let preferredFileExtension = normalizedFileExtension(item.preferredFileExtension) {
            return normalizedFileName + "." + preferredFileExtension
        }

        guard let urlFileExtension = normalizedFileExtension(item.url.pathExtension) else {
            return normalizedFileName
        }

        return normalizedFileName + "." + urlFileExtension
    }

    /// Normalizes a file extension used for generated preview file names.
    private static func normalizedFileExtension(_ fileExtension: String?) -> String? {
        let normalizedFileExtension = fileExtension?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard
            let normalizedFileExtension,
            !normalizedFileExtension.isEmpty,
            normalizedFileExtension != "data"
        else {
            return nil
        }

        return normalizedFileExtension
    }

    /// Characters replaced in temporary QuickLook file names.
    private static let invalidFileNameCharacters = Set<Character>("/\\:")
}

extension FilePreviewViewController: QLPreviewControllerDataSource {

    /// Returns the number of items available for QuickLook preview.
    package func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        quickLookItems.count
    }

    /// Returns the QuickLook item for the requested index.
    package func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int
    ) -> QLPreviewItem {
        quickLookItems[index]
    }
}

/// QuickLook item wrapper around the SDK file preview model.
private final class FileQuickLookItem: NSObject, QLPreviewItem {

    /// URL opened by QuickLook.
    let previewItemURL: URL?

    /// Title displayed by QuickLook.
    let previewItemTitle: String?

    /// Creates a QuickLook item from SDK preview metadata and a prepared preview URL.
    init(
        item: FilePreviewItem,
        previewURL: URL
    ) {
        previewItemURL = previewURL
        previewItemTitle = item.displayName
        super.init()
    }
}
