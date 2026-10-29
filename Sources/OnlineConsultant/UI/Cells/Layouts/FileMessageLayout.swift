import CoreGraphics

/// Measures file attachment message bubbles.
package enum FileMessageLayout {

    /// Default content width used when file names are shorter than the base file block.
    package static let defaultContentWidth: CGFloat = 208
    /// Top inset used when the author line is hidden.
    package static let bubbleTopInsetWithoutAuthor: CGFloat = 2.5
    /// Bottom inset specific to compact file bubbles.
    package static let bubbleBottomInset: CGFloat = 2.5
    /// Fixed height of one rendered file row.
    package static let fileBlockHeight: CGFloat = 50
    /// Fixed size of the file icon container.
    package static let fileIconSize: CGFloat = 42

    /// Returns the preferred bubble width for one or more file rows.
    package static func preferredBubbleWidth(
        maxBubbleWidth: CGFloat,
        fileNameWidths: [CGFloat],
        fileSizeWidths: [CGFloat],
        authorWidth: CGFloat,
        metadataWidth: CGFloat
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let measuredTextWidth = max(
            fileNameWidths.max() ?? 0,
            fileSizeWidths.max() ?? 0
        )
        let measuredFileWidth = fileIconSize
            + MessageLayout.contentItemSpacing
            + measuredTextWidth
        let contentWidth = min(
            maxContentWidth,
            max(defaultContentWidth, measuredFileWidth, authorWidth, metadataWidth)
        )

        return ceil(contentWidth + MessageLayout.bubbleHorizontalInset * 2)
    }

    /// Returns the full cell height for a file message with the given row count.
    package static func preferredHeight(
        showsAuthor: Bool,
        itemCount: Int = 1
    ) -> CGFloat {
        let itemCount = max(1, itemCount)
        let authorHeight = showsAuthor
            ? MessageLayout.secondaryLineHeight
            : 0
        let topInset = showsAuthor
            ? MessageLayout.bubbleVerticalInset
            : bubbleTopInsetWithoutAuthor
        let visibleItemsCount = (showsAuthor ? 1 : 0) + itemCount + 1
        let spacingHeight = CGFloat(visibleItemsCount - 1) * MessageLayout.compactSpacing
        let bubbleHeight = topInset
            + bubbleBottomInset
            + authorHeight
            + CGFloat(itemCount) * fileBlockHeight
            + MessageLayout.secondaryLineHeight
            + spacingHeight

        return ceil(bubbleHeight + MessageLayout.compactSpacing * 2)
    }
}
