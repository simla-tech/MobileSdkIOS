import Foundation

/// Local UI state for a file selected in the message input before it is sent.
 package struct InputAttachment: Equatable, Sendable {

    /// Stable local identifier used to track upload and preview updates.
     package let id: UUID

    /// Original file name displayed in the input attachment list.
     package let fileName: String

    /// MIME content type used for upload and message item creation.
     package let contentType: String

    /// Optional local preview image data displayed while the file is attached.
     package let previewData: Data?

    /// Message item type sent to backend after upload, for example `file` or `image`.
     package let messageType: String

    /// Current upload state for this attachment.
     package let status: InputAttachmentStatus

    /// Indicates whether this attachment is ready to be sent in a message.
     package var canSend: Bool {
        if case .uploaded = status {
            return true
        }

        return false
    }

    /// Uploaded backend file identifier, if upload has completed.
     package var uploadedFileID: FlexibleID? {
        status.uploadedFileID
    }

    /// Creates local attachment state for a selected file.
     package init(
        id: UUID = UUID(),
        fileName: String,
        contentType: String = "application/octet-stream",
        previewData: Data? = nil,
        messageType: String = "file",
        status: InputAttachmentStatus = .uploading
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.previewData = previewData
        self.messageType = messageType
        self.status = status
    }

    /// Returns a copy with a new upload status.
    package func updatingStatus(_ status: InputAttachmentStatus) -> InputAttachment {
        InputAttachment(
            id: id,
            fileName: fileName,
            contentType: contentType,
            previewData: previewData,
            messageType: messageType,
            status: status
        )
    }

    /// Returns a copy with updated local preview data.
    package func updatingPreviewData(_ previewData: Data?) -> InputAttachment {
        InputAttachment(
            id: id,
            fileName: fileName,
            contentType: contentType,
            previewData: previewData,
            messageType: messageType,
            status: status
        )
    }
}
