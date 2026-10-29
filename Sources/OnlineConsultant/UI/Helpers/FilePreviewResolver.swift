import Foundation

/// Resolves file preview candidates into a set of local files that Quick Look can present.
package enum FilePreviewResolver {

    /// Returns the item at `startIndex`, clamping the index to the available item range.
    package static func selectedItem(
        from items: [FilePreviewItem],
        startIndex: Int
    ) -> FilePreviewItem? {
        guard !items.isEmpty else {
            return nil
        }

        return items[min(max(startIndex, 0), items.count - 1)]
    }

    /// Trims an optional backend file identifier and returns `nil` when it is missing or empty.
    package static func normalizedFileID(_ fileID: String?) -> String? {
        let normalizedFileID = fileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedFileID?.isEmpty == false ? normalizedFileID : nil
    }

    /// Filters the provided items to locally available files and maps the selected item to its new index.
    package static func localPreviewItems(
        from items: [FilePreviewItem],
        startIndex: Int
    ) -> (items: [FilePreviewItem], startIndex: Int)? {
        guard !items.isEmpty else {
            return nil
        }

        let selectedIndex = min(max(startIndex, 0), items.count - 1)
        let selectedItem = items[selectedIndex]
        guard canPreviewLocalFile(selectedItem.url) else {
            return nil
        }

        let localItems = items.filter { canPreviewLocalFile($0.url) }
        guard
            let localStartIndex = localItems.firstIndex(where: {
                $0.id == selectedItem.id
                    && $0.url == selectedItem.url
            })
        else {
            return nil
        }

        return (localItems, localStartIndex)
    }

    /// Returns `true` when the URL points to an existing local file that can be passed to Quick Look.
    private static func canPreviewLocalFile(_ url: URL) -> Bool {
        url.isFileURL && FileManager.default.fileExists(atPath: url.path)
    }
}
