import CoreGraphics

/// Measures order message bubbles.
package enum OrderMessageLayout {

    /// Default minimum content width retained for outgoing messages.
    package static let defaultContentWidth: CGFloat = 251
    /// Spacing between tightly related order item or field labels.
    package static let innerSpacing: CGFloat = 2
    /// Maximum number of order item name lines; zero means unlimited.
    package static let itemNameMaxLines: CGFloat = 0

    /// Returns the preferred order bubble width from measured order content and metadata widths.
    package static func preferredBubbleWidth(
        maxBubbleWidth: CGFloat,
        orderContentWidth: CGFloat,
        authorWidth: CGFloat,
        metadataWidth: CGFloat,
        minimumContentWidth: CGFloat = defaultContentWidth
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let contentWidth = min(
            maxContentWidth,
            max(minimumContentWidth, orderContentWidth, authorWidth, metadataWidth)
        )

        return ceil(contentWidth + MessageLayout.bubbleHorizontalInset * 2)
    }

    /// Returns the full cell height for an order message.
    package static func preferredHeight(
        orderNumberHeight: CGFloat,
        itemHeights: [CGFloat],
        fieldHeights: [CGFloat],
        showsAuthor: Bool
    ) -> CGFloat {
        let authorHeight = showsAuthor
            ? MessageLayout.secondaryLineHeight
            : 0
        let visibleBlocksCount = (showsAuthor ? 1 : 0)
            + (orderNumberHeight > 0 ? 1 : 0)
            + itemHeights.count
            + fieldHeights.count
            + 1
        let spacingHeight = CGFloat(max(0, visibleBlocksCount - 1))
            * MessageLayout.bubbleContentSpacing
        let bubbleHeight = MessageLayout.bubbleVerticalInset * 2
            + authorHeight
            + orderNumberHeight
            + itemHeights.reduce(0, +)
            + fieldHeights.reduce(0, +)
            + MessageLayout.secondaryLineHeight
            + spacingHeight

        return ceil(bubbleHeight + MessageLayout.compactSpacing * 2)
    }
}
