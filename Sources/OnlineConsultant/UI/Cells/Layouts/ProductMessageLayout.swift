import CoreGraphics

/// Measures product message bubbles.
package enum ProductMessageLayout {

    /// Default minimum content width retained for outgoing messages.
    package static let defaultContentWidth: CGFloat = 214
    /// Right inset of incoming product text measured from the bubble edge in Figma.
    private static let incomingTextTrailingInset: CGFloat = 32

    package static func additionalTextTrailingInset(isOutgoing: Bool) -> CGFloat {
        isOutgoing ? 0 : incomingTextTrailingInset - MessageLayout.bubbleHorizontalInset
    }

    /// Fixed product image side length.
    package static let imageSize: CGFloat = 80
    /// Maximum number of title lines used for height normalization.
    package static let titleMaxLines: CGFloat = 2

    /// Returns the preferred product bubble width from measured text and metadata widths.
    package static func preferredBubbleWidth(
        maxBubbleWidth: CGFloat,
        titleWidth: CGFloat,
        priceWidth: CGFloat,
        quantityWidth: CGFloat,
        authorWidth: CGFloat,
        metadataWidth: CGFloat,
        minimumContentWidth: CGFloat = defaultContentWidth,
        additionalTextTrailingInset: CGFloat = 0
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let contentWidth = min(
            maxContentWidth,
            max(
                minimumContentWidth,
                imageSize,
                titleWidth + additionalTextTrailingInset,
                priceWidth + additionalTextTrailingInset,
                quantityWidth + additionalTextTrailingInset,
                authorWidth,
                metadataWidth
            )
        )

        return ceil(contentWidth + MessageLayout.bubbleHorizontalInset * 2)
    }

    /// Returns the full cell height for a product message.
    package static func preferredHeight(
        titleHeight: CGFloat,
        showsAuthor: Bool,
        showsPrice: Bool,
        showsQuantity: Bool
    ) -> CGFloat {
        let authorHeight = showsAuthor
            ? MessageLayout.secondaryLineHeight
            : 0
        let normalizedTitleHeight = max(
            MessageLayout.contentLineHeight,
            min(titleHeight, MessageLayout.contentLineHeight * titleMaxLines)
        )
        let infoLineCount = (showsPrice ? 1 : 0) + (showsQuantity ? 1 : 0)
        let infoHeight = CGFloat(infoLineCount) * MessageLayout.contentLineHeight
        let visibleItemsCount = 3
            + (showsAuthor ? 1 : 0)
            + (infoLineCount > 0 ? 1 : 0)
        let spacingHeight = CGFloat(max(0, visibleItemsCount - 1))
            * MessageLayout.bubbleContentSpacing
        let bubbleHeight = MessageLayout.bubbleVerticalInset * 2
            + authorHeight
            + normalizedTitleHeight
            + infoHeight
            + imageSize
            + MessageLayout.secondaryLineHeight
            + spacingHeight

        return ceil(bubbleHeight + MessageLayout.compactSpacing * 2)
    }
}
