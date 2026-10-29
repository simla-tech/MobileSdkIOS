import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Coordinates the complete input bar attachment flow for `OnlineConsultantViewController`.
///
/// The coordinator owns system picker presentation, file validation, upload tasks, retry payloads,
/// and removal of pending input attachments. It stays package-scoped because it depends on UIKit
/// presentation APIs and is wired by the ready-to-use view controller rather than by `ConsultantView`.
@MainActor
package final class InputBarAttachmentCoordinator: NSObject {

    /// View controller used to present action sheets and system pickers.
    package weak var presentingViewController: UIViewController?

    /// Called when an attachment operation fails and the host should show a generic error.
    package var onError: ((Error) -> Void)?

    /// Called when an attachment operation needs to show a title/message alert.
    package var onAlert: ((String, String) -> Void)?

    private static let maxInputAttachmentCount = 10
    private static let maxImageAttachmentFileSize = 3 * 1024 * 1024
    private static let maxDocumentAttachmentFileSize = 5 * 1024 * 1024

    private var controller: OnlineConsultantController?
    private var uploadAttachmentTasks: [UUID: Task<Void, Never>] = [:]
    private var inputAttachmentUploadPayloads: [UUID: InputAttachmentUploadPayload] = [:]

    private var remainingInputAttachmentSlots: Int {
        max(0, Self.maxInputAttachmentCount - (controller?.inputAttachments.count ?? 0))
    }

    private var hasFreeInputAttachmentSlot: Bool {
        remainingInputAttachmentSlots > 0
    }

    deinit {
        uploadAttachmentTasks.values.forEach { $0.cancel() }
    }

    /// Updates the controller used for creating, uploading, retrying, and removing input attachments.
    package func setController(_ controller: OnlineConsultantController?) {
        self.controller = controller
    }

    /// Cancels all active attachment upload tasks.
    package func cancelTasks() {
        uploadAttachmentTasks.values.forEach { $0.cancel() }
        uploadAttachmentTasks.removeAll()
    }

    /// Clears transient upload state when the bound consultant controller changes.
    package func resetState() {
        cancelTasks()
        inputAttachmentUploadPayloads.removeAll()
    }

    /// Cancels an upload, drops its retry payload, and removes the attachment from the controller.
    package func removeInputAttachment(id: UUID) {
        uploadAttachmentTasks[id]?.cancel()
        uploadAttachmentTasks[id] = nil
        inputAttachmentUploadPayloads[id] = nil
        controller?.removeInputAttachment(id: id)
    }

    /// Repeats upload for a failed input attachment when its original payload is still available.
    package func retryInputAttachment(id: UUID) {
        guard let payload = inputAttachmentUploadPayloads[id] else {
            showAlert(
                title: ConsultantLocalization.commonError.localized,
                message: ConsultantLocalization.attachmentErrorRetryUploadFailed.localized
            )
            return
        }

        uploadInputAttachment(id: id, payload: payload)
    }

    /// Drops retry payloads for attachments that are no longer present in the input bar.
    package func pruneUploadPayloads(keeping attachments: [InputAttachment]) {
        let attachmentIDs = Set(attachments.map(\.id))
        let payloadIDsToRemove = inputAttachmentUploadPayloads.keys.filter {
            !attachmentIDs.contains($0)
        }
        removeUploadPayloads(for: payloadIDsToRemove)
    }

    /// Drops retry payloads after the selected attachments are sent with a message.
    package func clearUploadPayloads(for attachments: [InputAttachment]) {
        removeUploadPayloads(for: attachments.map(\.id))
    }

    /// Presents the attachment source menu anchored to the input bar attachment button.
    package func showAttachmentMenu(sourceView: UIView) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(
            title: ConsultantLocalization.attachmentActionCamera.localized,
            style: .default
        ) { [weak self] _ in
            self?.showCameraPicker()
        })
        alert.addAction(UIAlertAction(
            title: ConsultantLocalization.attachmentActionPhotoOrVideo.localized,
            style: .default
        ) { [weak self] _ in
            self?.showPhotoPicker()
        })
        alert.addAction(UIAlertAction(
            title: ConsultantLocalization.commonFile.localized,
            style: .default
        ) { [weak self] _ in
            self?.showDocumentPicker()
        })
        alert.addAction(UIAlertAction(
            title: ConsultantLocalization.attachmentActionCancel.localized,
            style: .cancel
        ))

        if presentingViewController?.traitCollection.userInterfaceIdiom == .pad {
            alert.popoverPresentationController?.sourceView = sourceView
            alert.popoverPresentationController?.sourceRect = sourceView.bounds
        }

        presentingViewController?.present(alert, animated: true)
    }

    /// Presents camera capture after checking attachment count, camera permission text, and availability.
    private func showCameraPicker() {
        guard hasFreeInputAttachmentSlot else {
            showError(AttachmentPickerError.tooManyAttachments)
            return
        }

        let hasCameraUsageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil

        guard hasCameraUsageDescription else {
            showAlert(
                title: ConsultantLocalization.commonUnavailable.localized,
                message: ConsultantLocalization.attachmentErrorCameraMissingUsageDescription.localized
            )
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showAlert(
                title: ConsultantLocalization.commonUnavailable.localized,
                message: ConsultantLocalization.attachmentErrorCameraUnavailable.localized
            )
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [ImagePickerMetadata.imageMediaTypeIdentifier]
        picker.allowsEditing = false
        picker.delegate = self
        presentingViewController?.present(picker, animated: true)
    }

    /// Presents the system document picker for file attachments.
    private func showDocumentPicker() {
        guard hasFreeInputAttachmentSlot else {
            showError(AttachmentPickerError.tooManyAttachments)
            return
        }

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = self
        presentingViewController?.present(picker, animated: true)
    }

    /// Presents the system photo picker with selection limited by the remaining attachment slots.
    private func showPhotoPicker() {
        let remainingSlots = remainingInputAttachmentSlots
        guard remainingSlots > 0 else {
            showError(AttachmentPickerError.tooManyAttachments)
            return
        }

        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = remainingSlots

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presentingViewController?.present(picker, animated: true)
    }

    /// Validates picked image data and calls `onValidData` only when it can be uploaded.
    private func handlePickedImageData(
        _ data: Data?,
        failAttachmentID: UUID?,
        onValidData: (Data) -> Void
    ) {
        guard let data, !data.isEmpty else {
            handlePickedImageError(
                AttachmentPickerError.emptyImageData,
                failAttachmentID: failAttachmentID
            )
            return
        }

        do {
            try validateImageSize(data.count)
        } catch {
            handlePickedImageError(error, failAttachmentID: failAttachmentID)
            return
        }

        onValidData(data)
    }

    /// Marks an already-created picker attachment as failed and reports the error to the host.
    private func handlePickedImageError(
        _ error: Error,
        failAttachmentID: UUID?
    ) {
        if let failAttachmentID {
            controller?.failInputAttachment(
                id: failAttachmentID,
                message: error.localizedDescription
            )
        }

        showError(error)
    }

    /// Uploads data for an image attachment that was already inserted by the photo picker flow.
    private func uploadImageAttachment(
        id: UUID,
        data: Data,
        contentType: String
    ) {
        guard let controller else {
            showError(ConsultantControllerError.notConnected)
            return
        }

        guard controller.inputAttachments.contains(where: { $0.id == id }) else {
            return
        }

        let payload = InputAttachmentUploadPayload(
            data: data,
            contentType: contentType,
            previewData: data
        )

        storeAndUploadInputAttachment(id: id, payload: payload)
    }

    /// Creates a new file input attachment from document picker data and starts its upload.
    private func uploadFileAttachment(
        data: Data,
        fileName: String,
        contentType: String
    ) {
        uploadNewInputAttachment(
            data: data,
            fileName: fileName,
            contentType: contentType,
            previewData: nil,
            kind: .file
        )
    }

    /// Adds a new input attachment to the controller and stores the payload needed for retry.
    private func uploadNewInputAttachment(
        data: Data,
        fileName: String,
        contentType: String,
        previewData: Data?,
        kind: InputAttachmentKind
    ) {
        guard let controller else {
            showError(ConsultantControllerError.notConnected)
            return
        }

        let attachment = controller.addInputAttachment(
            fileName: fileName,
            contentType: contentType,
            previewData: previewData,
            messageType: kind.messageType
        )
        let payload = InputAttachmentUploadPayload(
            data: data,
            contentType: contentType,
            previewData: previewData
        )

        storeAndUploadInputAttachment(id: attachment.id, payload: payload)
    }

    /// Persists a retry payload and starts uploading it for the matching input attachment.
    private func storeAndUploadInputAttachment(
        id: UUID,
        payload: InputAttachmentUploadPayload
    ) {
        inputAttachmentUploadPayloads[id] = payload
        uploadInputAttachment(id: id, payload: payload)
    }

    /// Starts or replaces the upload task for an input attachment.
    private func uploadInputAttachment(
        id: UUID,
        payload: InputAttachmentUploadPayload
    ) {
        guard let controller else {
            showError(ConsultantControllerError.notConnected)
            return
        }

        guard controller.inputAttachments.contains(where: { $0.id == id }) else {
            return
        }

        uploadAttachmentTasks[id]?.cancel()
        uploadAttachmentTasks[id] = Task { [weak self, controller] in
            defer {
                self?.uploadAttachmentTasks[id] = nil
            }

            do {
                try await controller.uploadInputAttachment(
                    id: id,
                    data: payload.data,
                    contentType: payload.contentType,
                    previewData: payload.previewData
                )
            } catch ConsultantControllerError.inputAttachmentRemoved {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.showError(error)
            }
        }
    }

    /// Reads a security-scoped document URL, validates its size, and uploads it as a file attachment.
    private func loadFileAttachment(from url: URL) {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileSize = try url.fileSize()
            try validateDocumentFileSize(fileSize)

            let data = try Data(contentsOf: url)
            if fileSize == nil {
                try validateDocumentFileSize(data.count)
            }

            uploadFileAttachment(
                data: data,
                fileName: url.fileName,
                contentType: url.contentType
            )
        } catch {
            showError(error)
        }
    }

    /// Validates a document file size against the SDK upload limit.
    private func validateDocumentFileSize(_ fileSize: Int?) throws {
        guard let fileSize else {
            return
        }

        guard fileSize <= Self.maxDocumentAttachmentFileSize else {
            throw AttachmentPickerError.fileTooLarge
        }
    }

    /// Validates an image file size against the SDK upload limit.
    private func validateImageSize(_ fileSize: Int) throws {
        guard fileSize <= Self.maxImageAttachmentFileSize else {
            throw AttachmentPickerError.imageTooLarge
        }
    }

    private func showError(_ error: Error) {
        onError?(error)
    }

    private func showAlert(title: String, message: String) {
        onAlert?(title, message)
    }

    private func removeUploadPayloads<IDSequence: Sequence>(
        for ids: IDSequence
    ) where IDSequence.Element == UUID {
        ids.forEach { inputAttachmentUploadPayloads[$0] = nil }
    }

    package override init() {
        super.init()
    }
}

extension InputBarAttachmentCoordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    /// Dismisses camera capture when the user cancels it.
    package func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    /// Converts camera output into JPEG data and uploads it as an image input attachment.
    package func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage else {
            handlePickedImageError(
                AttachmentPickerError.emptyImageData,
                failAttachmentID: nil
            )
            return
        }

        handlePickedImageData(
            image.jpegData(compressionQuality: 0.9),
            failAttachmentID: nil
        ) { data in
            uploadNewInputAttachment(
                data: data,
                fileName: "photo-\(UUID().uuidString).jpg",
                contentType: "image/jpeg",
                previewData: data,
                kind: .image
            )
        }
    }
}

extension InputBarAttachmentCoordinator: UIDocumentPickerDelegate {

    /// Uploads the selected documents, respecting the remaining input attachment slots.
    package func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let remainingSlots = remainingInputAttachmentSlots
        guard remainingSlots > 0 else {
            showError(AttachmentPickerError.tooManyAttachments)
            return
        }

        if urls.count > remainingSlots {
            showError(AttachmentPickerError.tooManyAttachments)
        }

        urls.prefix(remainingSlots).forEach(loadFileAttachment)
    }
}

extension InputBarAttachmentCoordinator: PHPickerViewControllerDelegate {

    /// Creates placeholder image attachments and loads their binary data from the photo picker.
    package func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let controller else {
            showError(ConsultantControllerError.notConnected)
            return
        }

        results.forEach { result in
            let itemProvider = result.itemProvider
            let metadata = ImagePickerMetadata.make(from: itemProvider)
            let attachment = controller.addInputAttachment(
                fileName: metadata.fileName,
                contentType: metadata.contentType,
                messageType: InputAttachmentKind.image.messageType
            )

            loadImageAttachment(
                result,
                attachment: attachment,
                typeIdentifier: metadata.typeIdentifier,
                contentType: metadata.contentType
            )
        }
    }

    /// Loads image data from the picker item provider and uploads it into the existing attachment.
    private func loadImageAttachment(
        _ result: PHPickerResult,
        attachment: InputAttachment,
        typeIdentifier: String,
        contentType: String
    ) {
        let itemProvider = result.itemProvider

        itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    self.handlePickedImageError(error, failAttachmentID: attachment.id)
                    return
                }

                self.handlePickedImageData(
                    data,
                    failAttachmentID: attachment.id
                ) { imageData in
                    self.uploadImageAttachment(
                        id: attachment.id,
                        data: imageData,
                        contentType: contentType
                    )
                }
            }
        }
    }
}

private extension InputBarAttachmentCoordinator {

    /// Local input attachment kind mapped to the message type expected by the controller.
    enum InputAttachmentKind {
        case file
        case image

        package var messageType: String {
            switch self {
            case .file:
                return "file"
            case .image:
                return "image"
            }
        }
    }

    /// Upload payload retained while an input attachment can be retried.
    struct InputAttachmentUploadPayload {
        package let data: Data
        package let contentType: String
        package let previewData: Data?
    }
}
