import CoreGraphics

/// Measures plain text message bubbles.
package enum TextMessageLayout {

    /// Returns the maximum text content width for the given collection width.
    package static func maxTextWidth(
        collectionWidth: CGFloat
    ) -> CGFloat {
        max(
            1,
            collectionWidth * MessageLayout.bubbleMaxWidthMultiplier
                - MessageLayout.bubbleHorizontalInset * 2
        )
    }

    /// Returns the full cell height for a text message, including bubble insets and metadata.
    package static func preferredHeight(
        messageTextHeight: CGFloat,
        isOutgoing: Bool,
        showsAuthor: Bool? = nil,
        showsMetadata: Bool = true
    ) -> CGFloat {
        let showsAuthor = showsAuthor ?? !isOutgoing
        let authorHeight = showsAuthor ? MessageLayout.secondaryLineHeight : 0
        let visibleItemsCount = 1 + (showsAuthor ? 1 : 0) + (showsMetadata ? 1 : 0)
        let spacingHeight = CGFloat(visibleItemsCount - 1)
            * MessageLayout.bubbleContentSpacing
        let bubbleHeight = MessageLayout.bubbleVerticalInset * 2
            + authorHeight
            + ceil(messageTextHeight)
            + (showsMetadata ? MessageLayout.secondaryLineHeight : 0)
            + spacingHeight

        return max(
            MessageLayout.minimumCellHeight,
            ceil(bubbleHeight) + MessageLayout.compactSpacing * 2
        )
    }
}
