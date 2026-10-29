import Foundation

/// Coordinator for sending visitor messages through the backend REST API.
///
/// Creates local optimistic messages through callbacks, sends text or uploaded attachment payloads,
/// maps input attachments to backend `ConsultantSendMessageItem` values, keeps image preview data for
/// local rendering, replaces local messages with backend acknowledgements, and marks failed local
/// messages when sending does not complete.
@MainActor
package final class MessageSender {

    private let client: OnlineConsultantClient

    /// Creates a sender with the client used for message requests.
    package init(client: OnlineConsultantClient) {
        self.client = client
    }

    /// Sends a failed message again, keeping its existing row and uploaded attachment identifiers.
    package func retryMessage(
        _ message: ConsultantMessage,
        credentials: MessageSendCredentials,
        callbacks: MessageSenderCallbacks
    ) async throws {
        guard message.canRetrySending, let id = message.id?.value,
              let type = message.messageType else { return }
        let items = (message.items ?? []).compactMap { item -> ConsultantSendMessageItem? in
            guard let id = item.id else { return nil }
            return ConsultantSendMessageItem(id: id, caption: item.caption)
        }
        callbacks.updateLocalMessageStatus(id, .sending)
        do {
            let sentMessage = try await client.sendMessage(
                text: message.content,
                type: type,
                items: items,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )
            callbacks.replaceLocalMessage(id, sentMessage)
        } catch {
            callbacks.updateLocalMessageStatus(id, .failed)
            callbacks.handleError(error)
            throw error
        }
    }

    /// Sends a text message and reports local message mutations through callbacks.
    package func sendTextMessage(
        _ text: String,
        credentials: MessageSendCredentials,
        callbacks: MessageSenderCallbacks
    ) async throws {
        let localMessageID = callbacks.appendLocalMessage(text, .text, nil)

        do {
            let sentMessage = try await client.sendMessage(
                text,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )
            callbacks.replaceLocalMessage(localMessageID, sentMessage)
        } catch {
            callbacks.updateLocalMessageStatus(localMessageID, .failed)
            callbacks.handleError(error)
            throw error
        }
    }

    /// Sends uploaded attachments and their text as separate messages, tracking each result independently.
    package func sendAttachmentMessages(
        text: String,
        attachments: [InputAttachment],
        credentials: MessageSendCredentials,
        callbacks: MessageSenderCallbacks
    ) async throws {
        let outgoingMessages = try makeOutgoingMessages(
            text: text,
            attachments: attachments
        )
        let localMessageIDs = outgoingMessages.map { outgoingMessage in
            callbacks.appendLocalMessage(
                outgoingMessage.text,
                outgoingMessage.messageType,
                outgoingMessage.items.isEmpty ? nil : makeLocalMessageItems(
                    from: outgoingMessage.items,
                    attachments: outgoingMessage.attachments,
                    messageType: outgoingMessage.messageType
                )
            )
        }
        callbacks.removeInputAttachments(attachments.map(\.id))

        var firstError: Error?
        for (index, outgoingMessage) in outgoingMessages.enumerated() {
            let localMessageID = localMessageIDs[index]

            do {
                let sentMessage = try await client.sendMessage(
                    text: outgoingMessage.text.isEmpty ? nil : outgoingMessage.text,
                    type: outgoingMessage.messageType,
                    items: outgoingMessage.items,
                    session: credentials.sessionID,
                    userToken: credentials.userToken
                )
                callbacks.replaceLocalMessage(localMessageID, sentMessage)
            } catch {
                callbacks.updateLocalMessageStatus(localMessageID, .failed)
                callbacks.handleError(error)
                if firstError == nil { firstError = error }
                if error is CancellationError || Task.isCancelled {
                    localMessageIDs.dropFirst(index + 1).forEach {
                        callbacks.updateLocalMessageStatus($0, .failed)
                    }
                    break
                }
            }
        }
        if let firstError { throw firstError }
    }

    private func makeSendMessageItems(
        from attachments: [InputAttachment]
    ) throws -> [ConsultantSendMessageItem] {
        try attachments.map { attachment in
            guard let fileID = attachment.uploadedFileID else {
                throw ConsultantControllerError.inputAttachmentsNotReady
            }

            return ConsultantSendMessageItem(
                id: fileID.value,
                caption: attachment.fileName
            )
        }
    }

    private func makeOutgoingMessages(
        text: String,
        attachments: [InputAttachment]
    ) throws -> [OutgoingMessage] {
        let imageAttachments = attachments.filter { $0.messageType == "image" }
        let fileAttachments = attachments.filter { $0.messageType != "image" }

        var messages = try [
            makeOutgoingAttachmentMessage(messageType: .image, attachments: imageAttachments),
            makeOutgoingAttachmentMessage(messageType: .file, attachments: fileAttachments)
        ].compactMap { $0 }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            messages.append(OutgoingMessage(text: text, messageType: .text, attachments: [], items: []))
        }
        return messages
    }

    private func makeOutgoingAttachmentMessage(
        messageType: MessageType,
        attachments: [InputAttachment]
    ) throws -> OutgoingMessage? {
        guard !attachments.isEmpty else {
            return nil
        }

        return OutgoingMessage(
            text: "",
            messageType: messageType,
            attachments: attachments,
            items: try makeSendMessageItems(from: attachments)
        )
    }

    private func makeLocalMessageItems(
        from items: [ConsultantSendMessageItem],
        attachments: [InputAttachment],
        messageType: MessageType
    ) -> [MessageItem] {
        zip(items, attachments).map { item, attachment in
            var previewDataURL: String?

            if
                messageType == .image,
                let localPreviewDataURL = localImagePreviewDataURL(from: attachment)
            {
                previewDataURL = localPreviewDataURL
            }

            return MessageItem(
                id: item.id,
                caption: item.caption,
                url: previewDataURL
            )
        }
    }

    private func localImagePreviewDataURL(
        from attachment: InputAttachment
    ) -> String? {
        guard
            attachment.messageType == "image",
            attachment.contentType.hasPrefix("image/"),
            let previewData = attachment.previewData
        else {
            return nil
        }

        return "data:\(attachment.contentType);base64,\(previewData.base64EncodedString())"
    }
}

/// Callback set used by `MessageSender` to mutate controller-owned state.
///
/// Keeps the sender focused on building and performing send requests while the controller remains the
/// owner of message storage, input attachment removal, and error reporting.
package struct MessageSenderCallbacks {

    /// Appends a local outgoing message and returns its local identifier.
    package let appendLocalMessage: (String, MessageType, [MessageItem]?) -> String

    /// Removes sent input attachments from the input queue.
    package let removeInputAttachments: ([UUID]) -> Void

    /// Replaces a local message with backend acknowledgement data.
    package let replaceLocalMessage: (String, ConsultantSentMessage) -> Void

    /// Updates a local message delivery status.
    package let updateLocalMessageStatus: (String, MessageStatus) -> Void

    /// Handles an error produced by message sending.
    package let handleError: (Error) -> Void

    package init(
        appendLocalMessage: @escaping (String, MessageType, [MessageItem]?) -> String,
        removeInputAttachments: @escaping ([UUID]) -> Void,
        replaceLocalMessage: @escaping (String, ConsultantSentMessage) -> Void,
        updateLocalMessageStatus: @escaping (String, MessageStatus) -> Void,
        handleError: @escaping (Error) -> Void
    ) {
        self.appendLocalMessage = appendLocalMessage
        self.removeInputAttachments = removeInputAttachments
        self.replaceLocalMessage = replaceLocalMessage
        self.updateLocalMessageStatus = updateLocalMessageStatus
        self.handleError = handleError
    }
}

/// Credentials required for authorized backend send-message requests.
///
/// Groups the active session id and user token passed to the client when text or attachment messages
/// are sent.
package struct MessageSendCredentials {

    /// Current consultant session identifier.
    package let sessionID: String

    /// Current consultant user token.
    package let userToken: String

    package init(sessionID: String, userToken: String) {
        self.sessionID = sessionID
        self.userToken = userToken
    }
}

/// Local send unit created from prepared input attachments.
///
/// Represents one image group, file group, or standalone text message in a send operation.
private struct OutgoingMessage {

    /// Text that should be sent with this message.
    let text: String

    /// Message type used for the backend send request.
    let messageType: MessageType

    /// Input attachments represented by this outgoing message.
    let attachments: [InputAttachment]

    /// Backend send-message item payloads created from attachments.
    let items: [ConsultantSendMessageItem]
}
