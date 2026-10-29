import Foundation

/// Chat message returned by the consultant backend or created locally by the SDK for synthetic UI messages.
package struct ConsultantMessage: Codable, Equatable, Sendable {

    /// Backend message identifier from the `id` field.
    package let id: FlexibleID?

    /// Message text from the backend `content` field.
    package let content: String?

    /// Local SDK title used for contact-form messages.
    ///
    /// The backend `Message` response does not include this field.
    package let header: String?

    /// Product payload from the backend `product` field.
    package let product: MessageProduct?

    /// Order payload from the backend `order` field.
    package let order: MessageOrder?

    /// File or image items from the backend `items` field.
    package let items: [MessageItem]?

    /// Text of the quoted message from the backend `quote_content` field.
    package let quoteContent: String?

    /// Identifier of the quoted message from backend `quote_id`.
    package let quoteID: FlexibleID?

    /// Preview resolved from the currently loaded history; never encoded.
    package var resolvedQuotePreview: MessageQuotePreview? = nil

    /// Message creation time from the backend `time` field.
    package let time: String?

    /// Message update time from the backend `updated_at` field.
    package let updatedAt: String?

    /// Sender data from the backend `user` field.
    package let user: MessageUser?

    /// Direction flag from the backend `from_me` field.
    package let fromMe: Bool?

    /// Message type from the backend `type` field or a local SDK synthetic message type.
    package let messageType: MessageType?

    /// Delivery or read status from the backend `status` field or a local SDK synthetic message status.
    package let status: MessageStatus?

    /// Local SDK contact form payload used to render synthetic contact-form messages.
    ///
    /// The backend `Message` response does not include this field.
    package let contactForm: ContactForm?

    /// Creates a message instance for decoded backend messages, local outgoing messages, or SDK-generated UI messages.
    package init(
        id: FlexibleID? = nil,
        content: String? = nil,
        header: String? = nil,
        product: MessageProduct? = nil,
        order: MessageOrder? = nil,
        items: [MessageItem]? = nil,
        quoteContent: String? = nil,
        quoteID: FlexibleID? = nil,
        time: String? = nil,
        updatedAt: String? = nil,
        user: MessageUser? = nil,
        fromMe: Bool? = nil,
        messageType: MessageType? = nil,
        status: MessageStatus? = nil,
        contactForm: ContactForm? = nil
    ) {
        self.id = id
        self.content = content
        self.header = header
        self.product = product
        self.order = order
        self.items = items
        self.quoteContent = quoteContent
        self.quoteID = quoteID
        self.time = time
        self.updatedAt = updatedAt
        self.user = user
        self.fromMe = fromMe
        self.messageType = messageType
        self.status = status
        self.contactForm = contactForm
    }

    private enum CodingKeys: String, CodingKey {

        case id
        case content
        case header
        case product
        case order
        case items
        case quoteContent = "quote_content"
        case quoteID = "quote_id"
        case time
        case updatedAt = "updated_at"
        case user
        case fromMe = "from_me"
        case messageType = "type"
        case status
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(FlexibleID.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        product = try container.decodeIfPresent(MessageProduct.self, forKey: .product)
        order = try container.decodeIfPresent(MessageOrder.self, forKey: .order)
        items = try container.decodeIfPresent([MessageItem].self, forKey: .items)
        quoteContent = try container.decodeIfPresent(String.self, forKey: .quoteContent)
        quoteID = try container.decodeIfPresent(FlexibleID.self, forKey: .quoteID)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        user = try container.decodeIfPresent(MessageUser.self, forKey: .user)
        fromMe = try container.decodeIfPresent(Bool.self, forKey: .fromMe)
        messageType = try container.decodeIfPresent(MessageType.self, forKey: .messageType)
        status = try container.decodeIfPresent(MessageStatus.self, forKey: .status)
        contactForm = nil
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(product, forKey: .product)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(quoteContent, forKey: .quoteContent)
        try container.encodeIfPresent(quoteID, forKey: .quoteID)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(fromMe, forKey: .fromMe)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

package extension ConsultantMessage {

    /// Whether this failed outgoing message contains a payload that can be sent again.
    var canRetrySending: Bool {
        guard id != nil, fromMe == true, status == .failed else { return false }
        switch messageType {
        case .text:
            return content?.nilIfEmpty != nil
        case .image, .file:
            guard let items, !items.isEmpty else { return false }
            return items.allSatisfy { $0.id?.nilIfEmpty != nil }
        default:
            return false
        }
    }

    /// Local identifier used for the welcome message created from consultant `intro_text`.
    static let introMessageID = "_intro"

    /// Local identifier used for the offline message created from consultant offline configuration.
    static let offlineMessageID = "_offline"

    /// Indicates whether this message is the local welcome message shown for an empty chat.
    var isIntroMessage: Bool {
        id?.value == Self.introMessageID
    }

    /// Indicates whether this message is the local offline message shown while managers are unavailable.
    var isOfflineMessage: Bool {
        id?.value == Self.offlineMessageID
    }

    /// Indicates whether this message is a local SDK support message, not a backend chat item.
    var isVirtualSupportMessage: Bool {
        isIntroMessage || isOfflineMessage
    }

    /// Creates a local welcome text message from consultant `intro_text`.
    static func introMessage(text: String) -> ConsultantMessage {
        ConsultantMessage(
            id: FlexibleID(introMessageID),
            content: text,
            time: nil,
            user: MessageUser(
                firstName: ConsultantLocalization.messageAuthorBotAssistant.localized
            ),
            fromMe: false,
            messageType: .text,
            status: .seen
        )
    }

    /// Creates a local offline message from consultant offline configuration.
    static func offlineMessage(
        text: String?,
        contactForm: ContactForm?
    ) -> ConsultantMessage {
        ConsultantMessage(
            id: FlexibleID(offlineMessageID),
            content: text,
            time: nil,
            user: MessageUser(
                firstName: ConsultantLocalization.messageAuthorBotAssistant.localized
            ),
            fromMe: false,
            messageType: contactForm == nil ? .text : .contactForm,
            status: .seen,
            contactForm: contactForm
        )
    }

    /// Item identifiers that still need resolved file URLs.
    var unresolvedFileLinkItemIDs: [String] {
        guard messageType == .image || messageType == .file else {
            return []
        }

        return items?.compactMap { item in
            guard
                item.resolvedFileURL == nil
            else {
                return nil
            }

            return item.id
        } ?? []
    }

    /// Display models for image message items.
    var imageDisplayItems: [MessageFileDisplayItem] {
        guard messageType == .image else {
            return []
        }

        let fallbackDisplayName = ConsultantLocalization.messageItemImage.localized
        let parsedItems = displayFileItems(fallbackDisplayName: fallbackDisplayName)
        return parsedItems.isEmpty
            ? [.fallback(displayName: fallbackDisplayName)]
            : parsedItems
    }

    /// Display models for file message items.
    var fileDisplayItems: [MessageFileDisplayItem] {
        guard messageType == .file else {
            return []
        }

        let fallbackDisplayName = content?.nilIfEmpty
            ?? ConsultantLocalization.commonFile.localized
        let parsedItems = displayFileItems(fallbackDisplayName: fallbackDisplayName)
        return parsedItems.isEmpty
            ? [.fallback(displayName: fallbackDisplayName)]
            : parsedItems
    }

    /// Returns a copy of the message with a resolved file URL assigned to one item.
    func applyingFileLink(
        itemID: String,
        url: String
    ) -> ConsultantMessage {
        guard let items else {
            return self
        }

        let updatedItems = items.map { item -> MessageItem in
            guard item.id == itemID else {
                return item
            }

            return item.applyingFileLink(url)
        }

        return ConsultantMessage(
            id: id,
            content: content,
            header: header,
            product: product,
            order: order,
            items: updatedItems,
            quoteContent: quoteContent,
            quoteID: quoteID,
            time: time,
            updatedAt: updatedAt,
            user: user,
            fromMe: fromMe,
            messageType: messageType,
            status: status,
            contactForm: contactForm
        )
    }

    /// Returns a copy of the message with the provided local contact form payload.
    func applyingContactForm(_ contactForm: ContactForm?) -> ConsultantMessage {
        ConsultantMessage(
            id: id,
            content: content,
            header: header,
            product: product,
            order: order,
            items: items,
            quoteContent: quoteContent,
            quoteID: quoteID,
            time: time,
            updatedAt: updatedAt,
            user: user,
            fromMe: fromMe,
            messageType: messageType,
            status: status,
            contactForm: contactForm
        )
    }

    /// Returns a copy of the message with the provided delivery/read status.
    func applyingStatus(_ status: MessageStatus?) -> ConsultantMessage {
        ConsultantMessage(
            id: id,
            content: content,
            header: header,
            product: product,
            order: order,
            items: items,
            quoteContent: quoteContent,
            quoteID: quoteID,
            time: time,
            updatedAt: updatedAt,
            user: user,
            fromMe: fromMe,
            messageType: messageType,
            status: status,
            contactForm: contactForm
        )
    }

    /// Returns a copy that keeps existing values for fields omitted by a realtime update.
    func mergingMissingFields(from existing: ConsultantMessage) -> ConsultantMessage {
        let message = ConsultantMessage(
            id: id ?? existing.id,
            content: content ?? existing.content,
            header: header ?? existing.header,
            product: product ?? existing.product,
            order: order ?? existing.order,
            items: items ?? existing.items,
            quoteContent: quoteContent ?? existing.quoteContent,
            quoteID: quoteID ?? existing.quoteID,
            time: time ?? existing.time,
            updatedAt: updatedAt ?? existing.updatedAt,
            user: user ?? existing.user,
            fromMe: fromMe ?? existing.fromMe,
            messageType: messageType ?? existing.messageType,
            status: status ?? existing.status,
            contactForm: contactForm ?? existing.contactForm
        )

        return message.preservingResolvedFileLinks(from: existing)
    }

    /// Returns a copy that keeps previously resolved file metadata when the backend omits it.
    func preservingResolvedFileLinks(from existing: ConsultantMessage) -> ConsultantMessage {
        guard messageType == .image || messageType == .file else {
            return self
        }

        guard let items, !items.isEmpty else {
            guard let existingItems = existing.items, !existingItems.isEmpty else {
                return self
            }

            return ConsultantMessage(
                id: id,
                content: content,
                header: header,
                product: product,
                order: order,
                items: existingItems,
                quoteContent: quoteContent,
                quoteID: quoteID,
                time: time,
                updatedAt: updatedAt,
                user: user,
                fromMe: fromMe,
                messageType: messageType,
                status: status,
                contactForm: contactForm
            )
        }

        var existingItemsByID: [String: MessageItem] = [:]
        for item in existing.items ?? [] {
            guard
                let id = item.id,
                existingItemsByID[id] == nil
            else {
                continue
            }

            existingItemsByID[id] = item
        }

        guard !existingItemsByID.isEmpty else {
            return self
        }

        let updatedItems = items.map { item -> MessageItem in
            guard
                item.resolvedFileURL == nil,
                let id = item.id,
                let existingItem = existingItemsByID[id]
            else {
                return item
            }

            return item.preservingResolvedFileLink(from: existingItem)
        }

        guard updatedItems != items else {
            return self
        }

        return ConsultantMessage(
            id: id,
            content: content,
            header: header,
            product: product,
            order: order,
            items: updatedItems,
            quoteContent: quoteContent,
            quoteID: quoteID,
            time: time,
            updatedAt: updatedAt,
            user: user,
            fromMe: fromMe,
            messageType: messageType,
            status: status,
            contactForm: contactForm
        )
    }

    /// Parses raw file or image items into display models.
    private func displayFileItems(fallbackDisplayName: String) -> [MessageFileDisplayItem] {
        items?.compactMap { item in
            return MessageFileDisplayItem(
                id: item.id,
                displayName: item.displayFileName ?? fallbackDisplayName,
                sizeLabel: item.fileSizeLabel,
                urlString: item.resolvedFileURL,
                sourceImageSize: item.sourceImageSize
            )
        } ?? []
    }
}

package extension ConsultantMessage {

    /// Text copied from a message, including the visible contents of product and order cards.
    var clipboardText: String? {
        let lines: [String?]
        switch messageType {
        case .product where product != nil:
            lines = [productDisplayName, productPriceLabel, productQuantityLabel]
        case .order where order != nil:
            lines = [orderNumberLabel]
                + orderDisplayItems.map { item in
                    ["\(item.numberLabel) \(item.name)", item.details]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                }
                + orderDisplayFields.map { "\($0.title): \($0.value)" }
        default:
            return content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? content
                : nil
        }

        let text = lines.compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Formatted order number for order messages.
    var orderNumberLabel: String? {
        order?.formattedOrderNumberLabel
    }

    /// Display items for the order contents.
    var orderDisplayItems: [MessageOrderDisplayItem] {
        order?.displayItems ?? []
    }

    /// Display fields for the order summary.
    var orderDisplayFields: [MessageOrderDisplayField] {
        order?.displayFields ?? []
    }
}

package extension ConsultantMessage {

    /// Product name for UI display with a default fallback.
    var productDisplayName: String {
        let fallbackName = ConsultantLocalization.messageItemProduct.localized
        return product?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? product?.name ?? fallbackName
            : fallbackName
    }

    /// Formatted product price label.
    var productPriceLabel: String? {
        product?.cost?.formattedMoneyLabel
    }

    /// Formatted product quantity label.
    var productQuantityLabel: String? {
        product?.quantity?.formattedQuantityLabel(defaultUnit: product?.unit)
    }
}

package extension ConsultantMessage {

    /// Quote preview shown above the message body.
    var quotePreview: MessageQuotePreview? {
        if let resolvedQuotePreview {
            return resolvedQuotePreview
        }
        if let quoteText = quoteContent?.nilIfEmpty {
            return .text(quoteText)
        }
        return quoteID == nil ? nil : .text(ConsultantLocalization.messageQuotePlaceholder.localized)
    }
}

// grouping
package extension ConsultantMessage {

    /// Indicates whether two adjacent messages can be grouped by sender.
    func hasSameSender(as other: ConsultantMessage) -> Bool {
        guard fromMe == other.fromMe else {
            return false
        }

        guard fromMe != true else {
            return true
        }

        return incomingSenderIdentity == other.incomingSenderIdentity
    }

    /// Stable grouping identity for incoming sender data.
    private var incomingSenderIdentity: String {
        let firstName = normalizedSenderPart(user?.firstName)
        let lastName = normalizedSenderPart(user?.lastName)
        let avatar = normalizedSenderPart(user?.avatar)
        let identity = [firstName, lastName, avatar].joined(separator: "|")

        return identity == "||" ? "incoming" : identity
    }

    /// Normalizes one sender identity component.
    private func normalizedSenderPart(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

package extension ConsultantMessage {

    /// First remote or preinstalled image attached to a contact form.
    var contactFormImage: ContactFormMessageImage? {
        items?.compactMap { item in
            if let url = ActionImage.remoteURL(from: item.resolvedFileURL) {
                return ContactFormMessageImage(
                    url: url,
                    size: item.sourceImageSize
                )
            }

            guard
                let actionImage = ActionImage(preinstalledID: item.id),
                let url = actionImage.preinstalledURL
            else {
                return nil
            }

            return ContactFormMessageImage(
                url: url,
                size: actionImage.preinstalledSize
            )
        }.first
    }
}

package extension ConsultantMessage {

    /// File preview items that can be opened from a file message.
    var filePreviewItems: [FilePreviewItem] {
        guard messageType == .file else {
            return []
        }

        return fileDisplayItems.compactMap { item in
            guard
                let urlString = item.urlString,
                let url = URL(string: urlString)
            else {
                return nil
            }

            return FilePreviewItem(
                id: item.id,
                url: url,
                displayName: item.displayName,
                sizeLabel: item.sizeLabel
            )
        }
    }

    /// Image preview items that can be opened from an image message.
    var imagePreviewItems: [ImagePreviewItem] {
        guard messageType == .image else {
            return []
        }

        return imageDisplayItems.compactMap { item in
            guard
                let urlString = item.urlString,
                let url = URL(string: urlString)
            else {
                return nil
            }

            return ImagePreviewItem(
                id: item.id,
                url: url,
                caption: item.displayName
            )
        }
    }
}

package extension ConsultantMessage {

    /// Parsed date used to sort messages in the chat.
    var chatSortDate: Date? {
        guard let value = time ?? updatedAt else {
            return nil
        }

        return DateParser.date(from: value)
    }
}
