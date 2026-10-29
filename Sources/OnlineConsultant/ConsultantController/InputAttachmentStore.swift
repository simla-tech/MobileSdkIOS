import Foundation

/// Local store for attachments prepared in the message input.
///
/// Owns the ordered input attachment list, creates upload placeholders, updates upload status and
/// preview data, exposes send readiness, and removes attachments after sending or user actions. It
/// does not perform uploads itself; network work stays in the controller/client layer.
package struct InputAttachmentStore {

    /// Attachments currently prepared in the message input.
    package private(set) var attachments: [InputAttachment] = []

    /// Indicates whether every prepared attachment is ready to be sent.
    package var canSend: Bool {
        attachments.allSatisfy(\.canSend)
    }

    /// Creates and appends a new input attachment.
    @discardableResult
    package mutating func add(
        fileName: String,
        contentType: String = "application/octet-stream",
        previewData: Data? = nil,
        messageType: String = "file"
    ) -> InputAttachment {
        let attachment = InputAttachment(
            fileName: fileName,
            contentType: contentType,
            previewData: previewData,
            messageType: messageType,
            status: .uploading
        )
        attachments.append(attachment)
        return attachment
    }

    /// Returns the attachment with the matching local id.
    package func attachment(id: UUID) -> InputAttachment? {
        attachments.first { $0.id == id }
    }

    /// Updates upload status for an existing attachment.
    @discardableResult
    package mutating func updateStatus(
        id: UUID,
        status: InputAttachmentStatus
    ) -> InputAttachment? {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        guard attachments[index].status != status else {
            return attachments[index]
        }

        let attachment = attachments[index].updatingStatus(status)
        attachments[index] = attachment
        return attachment
    }

    /// Updates preview data for an existing attachment.
    package mutating func updatePreviewData(
        id: UUID,
        previewData: Data
    ) -> Bool {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return false
        }

        guard attachments[index].previewData != previewData else {
            return false
        }

        attachments[index] = attachments[index].updatingPreviewData(previewData)
        return true
    }

    /// Removes an attachment by local id.
    package mutating func remove(id: UUID) -> Bool {
        let oldCount = attachments.count
        attachments.removeAll { $0.id == id }
        return attachments.count != oldCount
    }

    /// Removes attachments by local ids.
    package mutating func remove(ids: [UUID]) -> Bool {
        let ids = Set(ids)
        let oldCount = attachments.count
        attachments.removeAll { ids.contains($0.id) }
        return attachments.count != oldCount
    }

    /// Removes every stored input attachment.
    package mutating func removeAll() -> Bool {
        guard !attachments.isEmpty else {
            return false
        }

        attachments.removeAll()
        return true
    }

    package init(attachments: [InputAttachment] = []) {
        self.attachments = attachments
    }
}
