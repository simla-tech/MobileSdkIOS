import UIKit

/// Coordinates attachment preview preparation for message bubbles.
///
/// The coordinator resolves already cached files, downloads remote preview files when needed,
/// tracks loading identifiers for file and image bubbles, and presents the ready Quick Look preview.
@MainActor
package final class MessageAttachmentCoordinator {

    /// View controller used to present attachment previews.
    package weak var presentingViewController: UIViewController?

    /// Called when downloading a remote preview file fails.
    package var onError: ((Error) -> Void)?

    /// Called whenever loading state for file-message previews changes.
    package var onLoadingFilePreviewIDsChange: ((Set<String>) -> Void)?

    /// Called whenever loading state for image-message previews changes.
    package var onLoadingImagePreviewIDsChange: ((Set<String>) -> Void)?

    private var controller: OnlineConsultantController?
    private var filePreviewTasks: [String: Task<Void, Never>] = [:]
    private var loadingFilePreviewIDs: Set<String> = []
    private var loadingImagePreviewIDs: Set<String> = []

    deinit {
        filePreviewTasks.values.forEach { $0.cancel() }
    }

    /// Updates the controller used for cached file lookup and remote preview downloads.
    package func setController(_ controller: OnlineConsultantController?) {
        self.controller = controller
    }

    /// Cancels all active remote preview downloads.
    package func cancelTasks() {
        filePreviewTasks.values.forEach { $0.cancel() }
        filePreviewTasks.removeAll()
    }

    /// Clears transient preview state when the bound consultant controller changes.
    package func resetState() {
        cancelTasks()
        resetPreviewLoading()
    }

    /// Opens an image preview, converting image-specific items to generic file preview items first.
    package func showImagePreview(
        items: [ImagePreviewItem],
        startIndex: Int
    ) {
        showAttachmentPreview(
            items: items.enumerated().map { index, item in
                item.filePreviewItem(index: index)
            },
            startIndex: startIndex,
            kind: .image
        )
    }

    /// Opens a file preview from file-message preview items.
    package func showFilePreview(
        items: [FilePreviewItem],
        startIndex: Int
    ) {
        showAttachmentPreview(
            items: items,
            startIndex: startIndex,
            kind: .file
        )
    }

    private func showAttachmentPreview(
        items: [FilePreviewItem],
        startIndex: Int,
        kind: MessageAttachmentKind
    ) {
        let cachedItems = filePreviewItemsByApplyingCachedFiles(items)
        if let preview = FilePreviewResolver.localPreviewItems(
            from: cachedItems,
            startIndex: startIndex
        ) {
            presentFilePreview(preview)
            return
        }

        guard let selectedItem = FilePreviewResolver.selectedItem(
            from: cachedItems,
            startIndex: startIndex
        ) else {
            return
        }

        cacheAndPresentRemotePreview(
            selectedItem: selectedItem,
            cachedItems: cachedItems,
            startIndex: startIndex,
            kind: kind
        )
    }

    private func cacheAndPresentRemotePreview(
        selectedItem: FilePreviewItem,
        cachedItems: [FilePreviewItem],
        startIndex: Int,
        kind: MessageAttachmentKind
    ) {
        guard
            !selectedItem.url.isFileURL,
            let fileID = FilePreviewResolver.normalizedFileID(selectedItem.id),
            let controller,
            filePreviewTasks[fileID] == nil
        else {
            return
        }

        setPreviewLoading(true, fileID: fileID, kind: kind)
        filePreviewTasks[fileID] = Task { [weak self, controller] in
            defer {
                self?.filePreviewTasks[fileID] = nil
                self?.setPreviewLoading(false, fileID: fileID, kind: kind)
            }

            do {
                let localURL = try await controller.cacheRemoteFile(
                    fileID: fileID,
                    remoteURL: selectedItem.url
                )
                guard !Task.isCancelled else {
                    return
                }

                let resolvedItems = cachedItems.map { item in
                    FilePreviewResolver.normalizedFileID(item.id) == fileID
                        ? item.replacingURL(localURL)
                        : item
                }
                guard let preview = FilePreviewResolver.localPreviewItems(
                    from: resolvedItems,
                    startIndex: startIndex
                ) else {
                    return
                }

                self?.presentFilePreview(preview)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.onError?(error)
            }
        }
    }

    private func presentFilePreview(
        _ preview: (items: [FilePreviewItem], startIndex: Int)
    ) {
        guard
            let presentingViewController,
            presentingViewController.presentedViewController == nil
        else {
            return
        }

        let viewController = FilePreviewViewController(
            items: preview.items,
            startIndex: preview.startIndex
        )
        presentingViewController.present(viewController, animated: true)
    }

    private func filePreviewItemsByApplyingCachedFiles(
        _ items: [FilePreviewItem]
    ) -> [FilePreviewItem] {
        guard let controller else {
            return items
        }

        return items.map { item in
            guard
                let fileID = FilePreviewResolver.normalizedFileID(item.id),
                let cachedURL = controller.cachedFileURL(fileID: fileID)
            else {
                return item
            }

            return item.replacingURL(cachedURL)
        }
    }

    private func setPreviewLoading(
        _ isLoading: Bool,
        fileID: String,
        kind: MessageAttachmentKind
    ) {
        switch kind {
        case .file:
            if isLoading {
                loadingFilePreviewIDs.insert(fileID)
            } else {
                loadingFilePreviewIDs.remove(fileID)
            }
            onLoadingFilePreviewIDsChange?(loadingFilePreviewIDs)
        case .image:
            if isLoading {
                loadingImagePreviewIDs.insert(fileID)
            } else {
                loadingImagePreviewIDs.remove(fileID)
            }
            onLoadingImagePreviewIDsChange?(loadingImagePreviewIDs)
        }
    }

    private func resetPreviewLoading() {
        loadingFilePreviewIDs = []
        loadingImagePreviewIDs = []
        onLoadingFilePreviewIDsChange?([])
        onLoadingImagePreviewIDsChange?([])
    }

    package init() {}
}

private extension MessageAttachmentCoordinator {

    enum MessageAttachmentKind {
        case file
        case image
    }
}
