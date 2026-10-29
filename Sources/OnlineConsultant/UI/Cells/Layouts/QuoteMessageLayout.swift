import CoreGraphics

/// Measures quote message bubbles with a quoted preview and optional body text.
package enum QuoteMessageLayout {

    /// Width of the vertical quote indicator.
    package static let quoteBarWidth: CGFloat = 2
    /// Spacing between the quote indicator and quoted content.
    package static let quoteBarContentSpacing: CGFloat = 10
    /// Minimum height reserved for a text quote preview.
    package static let quoteTextMinHeight: CGFloat = 40
    package static let verticalInset: CGFloat = 8
    package static let authorHeight: CGFloat = 20
    package static let thumbnailSize: CGFloat = 40
    package static let thumbnailSpacing: CGFloat = 8

    /// Returns the preferred quote bubble width from measured content parts.
    package static func preferredBubbleWidth(
        maxBubbleWidth: CGFloat,
        authorWidth: CGFloat,
        bodyWidth: CGFloat,
        quoteWidth: CGFloat,
        metadataWidth: CGFloat
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let contentWidth = min(
            maxContentWidth,
            max(authorWidth, bodyWidth, quoteWidth, metadataWidth)
        )

        return ceil(contentWidth + MessageLayout.bubbleHorizontalInset * 2)
    }

    /// Returns the fixed preview height for a quote preview kind.
    package static func quotePreviewHeight(for preview: MessageQuotePreview) -> CGFloat {
        switch preview {
        case .text:
            return quoteTextMinHeight
        case .attachments(let items, let isImage, let text, _):
            return CGFloat(items.count) * attachmentRowHeight(isImage: isImage)
                + (text == nil ? 0 : quoteTextMinHeight)
        }
    }

    package static func attachmentRowHeight(isImage: Bool) -> CGFloat {
        isImage ? 52 : 48
    }

    /// Returns the full cell height for a quote message.
    package static func preferredHeight(
        bodyHeight: CGFloat,
        preview: MessageQuotePreview,
        showsAuthor: Bool
    ) -> CGFloat {
        let authorHeight = showsAuthor
            ? authorHeight
            : 0
        let quoteHeight = quotePreviewHeight(for: preview)
        let bodyHeight = bodyHeight > 0 ? bodyHeight : 0
        let visibleItemsCount = 2
            + (showsAuthor ? 1 : 0)
            + (bodyHeight > 0 ? 1 : 0)
        let spacingHeight = CGFloat(max(0, visibleItemsCount - 1))
            * MessageLayout.bubbleContentSpacing
        let bubbleHeight = verticalInset * 2
            + authorHeight
            + quoteHeight
            + bodyHeight
            + MessageLayout.secondaryLineHeight
            + spacingHeight

        return ceil(bubbleHeight + MessageLayout.compactSpacing * 2)
    }
}
