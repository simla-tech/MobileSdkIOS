import Foundation

/// Local store for chat messages known by `ConsultantController`.
///
/// Owns the ordered message list and centralizes message mutations: replacing connect results,
/// merging loaded pages, applying realtime inserts/updates/deletes, creating temporary outgoing
/// messages, replacing them with backend acknowledgements, applying resolved file links, and updating
/// action contact-form messages.
package struct MessageStore {

    /// Messages currently known by the controller.
    package private(set) var messages: [ConsultantMessage] = []

    /// Resolves attachment quotes against loaded history, including newly loaded pages and file URLs.
    package var messagesWithResolvedQuotes: [ConsultantMessage] {
        let originals = Dictionary(messages.compactMap { message in
            message.id.map { ($0.value, message) }
        }, uniquingKeysWith: { _, latest in latest })
        return messages.map { message in
            guard let quoteID = message.quoteID?.value,
                  quoteID != message.id?.value,
                  let original = originals[quoteID],
                  original.status != .deleted else { return message }
            var result = message
            if let items = original.items, !items.isEmpty,
               original.messageType == .file || original.messageType == .image {
                result.resolvedQuotePreview = .attachments(
                    items, isImage: original.messageType == .image,
                    text: message.quoteContent?.nilIfEmpty ?? original.content?.nilIfEmpty,
                    author: original.fromMe == true
                        ? ConsultantLocalization.messageQuoteAuthorYou.localized
                        : original.user?.displayName(isOutgoing: false)
                            ?? MessageUser.fallbackDisplayName(isOutgoing: false)
                )
            } else if let text = message.quoteContent?.nilIfEmpty ?? original.content?.nilIfEmpty {
                result.resolvedQuotePreview = .text(text)
            }
            return result
        }
    }

    /// Number of messages currently stored.
    package var messageCount: Int {
        messages.count
    }

    /// Indicates whether the store has no messages.
    package var isEmpty: Bool {
        messages.isEmpty
    }

    /// File item identifiers that still need resolved file URLs.
    package var unresolvedFileLinkItemIDs: Set<String> {
        Set(messages.flatMap(\.unresolvedFileLinkItemIDs))
    }

    /// Number of unread incoming messages in the loaded message list.
    package var unreadIncomingMessagesCount: Int {
        messages.reduce(0) { count, message in
            let isUnread = message.fromMe == false
                && message.status != .seen
                && message.status != .deleted
                && !message.isVirtualSupportMessage
            return count + (isUnread ? 1 : 0)
        }
    }

    /// Marks incoming backend messages with ids up to the provided id as seen.
    package mutating func markIncomingMessagesSeen(upTo messageID: String) -> Bool {
        guard let lastReadMessageID = UInt64(messageID) else {
            return false
        }

        var didUpdate = false
        messages = messages.map { message in
            guard
                message.fromMe == false,
                message.status != .seen,
                message.status != .deleted,
                let id = message.id?.value,
                let numericID = UInt64(id),
                numericID <= lastReadMessageID
            else {
                return message
            }

            didUpdate = true
            return message.applyingStatus(.seen)
        }

        return didUpdate
    }

    /// Latest known message update timestamp used as realtime reconnect watermark.
    package var latestKnownUpdatedAt: String? {
        messages
            .compactMap { $0.updatedAt ?? $0.time }
            .max()
    }

    /// Returns a message with the provided identifier, if it is stored.
    package func message(id: String) -> ConsultantMessage? {
        messages.first { $0.id?.value == id }
    }

    /// Removes every stored message.
    package mutating func reset() {
        messages = []
    }

    /// Replaces stored messages with a new array.
    package mutating func replaceAll(_ messages: [ConsultantMessage]) {
        self.messages = messages
    }

    /// Appends messages to the end of the store.
    package mutating func append(contentsOf messages: [ConsultantMessage]) {
        self.messages.append(contentsOf: messages)
    }

    /// Appends a local intro message when the current chat history is empty.
    private mutating func appendIntroMessageIfNeeded(text: String?) -> Bool {
        guard
            isEmpty,
            let introText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !introText.isEmpty
        else {
            return false
        }

        messages.append(.introMessage(text: introText))
        return true
    }

    /// Rebuilds local support messages from the current bootstrap configuration.
    package mutating func refreshVirtualSupportMessages(
        config: ConsultantConfig?,
        user: ContactFormUser,
        isOffline: Bool,
        hasSubmittedOfflineForm: Bool
    ) -> Bool {
        let oldMessages = messages
        messages.removeAll { $0.isVirtualSupportMessage }

        guard let config else {
            return messages != oldMessages
        }

        if isOffline, config.useOfflineMode {
            let offlineText = resolveOfflineText(config)
            messages.append(
                .offlineMessage(
                    text: offlineText,
                    contactForm: makeOfflineContactForm(
                        config: config,
                        text: offlineText,
                        user: user,
                        isSubmitted: hasSubmittedOfflineForm
                    )
                )
            )
        } else {
            _ = appendIntroMessageIfNeeded(text: config.introText)
        }

        return messages != oldMessages
    }

    /// Merges backend messages into the store by message identifier.
    package mutating func merge(_ newMessages: [ConsultantMessage]) {
        for message in newMessages {
            guard let messageID = message.id?.value else {
                appendBeforeVirtualSupportMessages(message)
                continue
            }

            if let index = messages.firstIndex(where: { $0.id?.value == messageID }) {
                messages[index] = message.preservingResolvedFileLinks(from: messages[index])
            } else {
                appendBeforeVirtualSupportMessages(message)
            }
        }
    }

    /// Applies a realtime message insert, update, or delete event.
    package mutating func applyRealtimeMessage(_ message: ConsultantMessage) {
        guard let messageID = message.id?.value else {
            appendBeforeVirtualSupportMessages(message)
            return
        }
        if message.status == .deleted {
            messages.removeAll { $0.id?.value == messageID }
            return
        }
        if let index = messages.firstIndex(where: { $0.id?.value == messageID }) {
            messages[index] = message.mergingMissingFields(from: messages[index])
            return
        }
        appendBeforeVirtualSupportMessages(message)
    }

    /// Adds a local outgoing message and returns its temporary identifier.
    package mutating func appendLocalOutgoingMessage(
        _ text: String,
        messageType: MessageType = .text,
        items: [MessageItem]? = nil
    ) -> String {
        let id = "_local_\(UUID().uuidString)"
        let timestamp = DateParser.string(from: Date())
        let message = ConsultantMessage(
            id: FlexibleID(id),
            content: text.isEmpty ? nil : text,
            items: items,
            time: timestamp,
            updatedAt: timestamp,
            user: MessageUser(),
            fromMe: true,
            messageType: messageType,
            status: .sending
        )

        appendBeforeVirtualSupportMessages(message)

        return id
    }

    /// Replaces a temporary local message with backend acknowledgement data.
    package mutating func replaceLocalMessage(
        id: String,
        sentMessage: ConsultantSentMessage
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id?.value == id }) else {
            return false
        }

        let localMessage = messages[index]
        let acknowledgedMessage = ConsultantMessage(
            id: FlexibleID(sentMessage.id),
            content: localMessage.content,
            product: localMessage.product,
            order: localMessage.order,
            items: localMessage.items,
            quoteContent: localMessage.quoteContent,
            quoteID: localMessage.quoteID,
            time: sentMessage.time,
            updatedAt: sentMessage.updatedAt ?? sentMessage.time,
            user: localMessage.user,
            fromMe: localMessage.fromMe ?? true,
            messageType: localMessage.messageType ?? .text,
            status: sentMessage.status,
            contactForm: localMessage.contactForm
        )

        if let duplicateIndex = messages.firstIndex(where: { $0.id?.value == sentMessage.id }) {
            let mergedMessage = messages[duplicateIndex].mergingMissingFields(from: acknowledgedMessage)

            if duplicateIndex < index {
                messages.remove(at: duplicateIndex)
                messages[index - 1] = mergedMessage
            } else {
                messages[index] = mergedMessage
                messages.remove(at: duplicateIndex)
            }
        } else {
            messages[index] = acknowledgedMessage
        }

        return true
    }

    /// Updates delivery status for a temporary local message.
    package mutating func updateLocalMessageStatus(
        id: String,
        status: MessageStatus
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id?.value == id }) else {
            return false
        }

        let message = messages[index]
        messages[index] = ConsultantMessage(
            id: message.id,
            content: message.content,
            product: message.product,
            order: message.order,
            items: message.items,
            quoteContent: message.quoteContent,
            quoteID: message.quoteID,
            time: message.time,
            updatedAt: DateParser.string(from: Date()),
            user: message.user,
            fromMe: message.fromMe,
            messageType: message.messageType,
            status: status,
            contactForm: message.contactForm
        )

        return true
    }

    /// Applies resolved backend file links to matching message items.
    package mutating func applyFileLinks(_ links: [String: String]) -> Bool {
        let updatedMessages = messages.map {
            links.reduce($0) { message, link in
                message.applyingFileLink(
                    itemID: link.key,
                    url: link.value
                )
            }
        }

        guard updatedMessages != messages else {
            return false
        }

        messages = updatedMessages
        return true
    }

    /// Marks an action contact-form message as submitted.
    package mutating func markActionContactFormSubmitted(actionID: FlexibleID?) -> Bool {
        guard let actionID = actionID?.value else {
            return false
        }

        guard let index = messages.firstIndex(where: { message in
            message.contactForm?.actionID?.value == actionID
        }) else {
            return false
        }

        let message = messages[index]
        guard message.contactForm?.isSubmitted != true else {
            return false
        }

        messages[index] = message.applyingContactForm(message.contactForm?.submitted())
        return true
    }

    /// Marks the local offline contact-form message as submitted.
    package mutating func markOfflineContactFormSubmitted() -> Bool {
        updateOfflineContactForm { $0.submitted() }
    }

    /// Updates an action contact-form message with a transformed form value.
    package mutating func updateActionContactForm(
        actionID: FlexibleID?,
        transform: (ContactForm) -> ContactForm
    ) -> Bool {
        guard let actionID = actionID?.value else {
            return false
        }

        return updateContactForm(matching: { message in
            message.contactForm?.actionID?.value == actionID
        }, transform: transform)
    }

    /// Updates the local offline contact-form message with a transformed form value.
    package mutating func updateOfflineContactForm(
        transform: (ContactForm) -> ContactForm
    ) -> Bool {
        updateContactForm(
            matching: { $0.isOfflineMessage },
            requiredKind: .offline,
            transform: transform
        )
    }

    private mutating func updateContactForm(
        matching matches: (ConsultantMessage) -> Bool,
        requiredKind: ContactFormKind? = nil,
        transform: (ContactForm) -> ContactForm
    ) -> Bool {
        guard let index = messages.firstIndex(where: matches),
              let contactForm = messages[index].contactForm else {
            return false
        }
        if let requiredKind, contactForm.kind != requiredKind {
            return false
        }
        let updatedContactForm = transform(contactForm)
        guard updatedContactForm != contactForm else {
            return false
        }

        messages[index] = messages[index].applyingContactForm(updatedContactForm)
        return true
    }

    private func makeOfflineContactForm(
        config: ConsultantConfig,
        text: String,
        user: ContactFormUser,
        isSubmitted: Bool
    ) -> ContactForm? {
        guard
            let fields = config.offlineForm?.fields,
            !fields.isEmpty
        else {
            return nil
        }

        return ContactForm(
            text: text,
            resultText: resolveOfflineFormResultText(config),
            kind: .offline,
            fields: fields,
            prefill: ContactFormPrefill(
                name: user.name,
                email: user.email,
                phone: user.phone
            ),
            isSubmitted: isSubmitted
        )
    }

    private func resolveOfflineText(_ config: ConsultantConfig) -> String {
        config.offlineText?.nilIfEmpty ?? ConsultantLocalization.offlineDefaultText.localized
    }

    private func resolveOfflineFormResultText(_ config: ConsultantConfig) -> String {
        config.offlineFormResultText?.nilIfEmpty
            ?? ConsultantLocalization.offlineFormDefaultResultText.localized
    }

    private mutating func appendBeforeVirtualSupportMessages(_ message: ConsultantMessage) {
        removeIntroMessage()

        guard let firstVirtualSupportIndex = messages.firstIndex(where: { $0.isVirtualSupportMessage }) else {
            messages.append(message)
            return
        }

        messages.insert(message, at: firstVirtualSupportIndex)
    }

    private mutating func removeIntroMessage() {
        messages.removeAll { $0.isIntroMessage }
    }

    package init(messages: [ConsultantMessage] = []) {
        self.messages = messages
    }
}
