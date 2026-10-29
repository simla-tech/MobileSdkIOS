import CoreGraphics

/// Measures image message bubbles and normalizes image sizes for display.
package enum ImageMessageLayout {

    /// Default image content width used when no source size is available.
    package static let contentWidth: CGFloat = 271
    /// Default image content height used when no source size is available.
    package static let contentHeight: CGFloat = 162
    /// Horizontal inset used by the metadata overlay inside image content.
    package static let metaOverlayHorizontalInset: CGFloat = 2

    /// Returns a fitted image size constrained by the maximum bubble width.
    package static func imageSize(
        maxBubbleWidth: CGFloat,
        sourceSize: CGSize? = nil
    ) -> CGSize {
        guard maxBubbleWidth > 0 else {
            return CGSize(width: contentWidth, height: contentHeight)
        }

        let maxContentWidth = min(
            contentWidth,
            max(1, maxBubbleWidth - MessageLayout.compactSpacing * 2)
        )
        let sourceSize = normalizedSourceSize(sourceSize)
        let scale = min(
            maxContentWidth / sourceSize.width,
            contentWidth / sourceSize.height
        )
        let contentWidth = max(1, floor(sourceSize.width * scale))

        return imageSize(contentWidth: contentWidth, sourceSize: sourceSize)
    }

    /// Returns a fitted image size for a collection width.
    package static func imageSize(
        collectionWidth: CGFloat,
        sourceSize: CGSize? = nil
    ) -> CGSize {
        let maxBubbleWidth = collectionWidth
            * MessageLayout.bubbleMaxWidthMultiplier

        return imageSize(maxBubbleWidth: maxBubbleWidth, sourceSize: sourceSize)
    }

    /// Returns an image size for an already resolved content width.
    package static func imageSize(
        contentWidth: CGFloat,
        sourceSize: CGSize? = nil
    ) -> CGSize {
        let width = max(1, contentWidth)
        let sourceSize = normalizedSourceSize(sourceSize)
        let height = ceil(width * sourceSize.height / sourceSize.width)

        return CGSize(width: ceil(width), height: height)
    }

    /// Returns the preferred bubble width for one or more image source sizes.
    package static func preferredBubbleWidth(
        maxBubbleWidth: CGFloat,
        sourceSizes: [CGSize?] = [nil]
    ) -> CGFloat {
        let imageWidths = normalizedSourceSizes(sourceSizes).map {
            imageSize(maxBubbleWidth: maxBubbleWidth, sourceSize: $0).width
        }
        return ceil(
            (imageWidths.max() ?? contentWidth)
                + MessageLayout.compactSpacing * 2
        )
    }

    /// Returns the preferred bubble width for a single image in a collection.
    package static func preferredBubbleWidth(
        collectionWidth: CGFloat,
        sourceSize: CGSize? = nil
    ) -> CGFloat {
        let maxBubbleWidth = collectionWidth
            * MessageLayout.bubbleMaxWidthMultiplier

        return preferredBubbleWidth(maxBubbleWidth: maxBubbleWidth, sourceSizes: [sourceSize])
    }

    /// Returns the full cell height for an image message, including optional author and image spacing.
    package static func preferredHeight(
        collectionWidth: CGFloat,
        sourceSizes: [CGSize?] = [nil],
        showsAuthor: Bool = false
    ) -> CGFloat {
        let imageSizes = normalizedSourceSizes(sourceSizes).map {
            imageSize(collectionWidth: collectionWidth, sourceSize: $0)
        }
        let authorHeight = showsAuthor
            ? MessageLayout.secondaryLineHeight
            : 0
        let authorSpacing = showsAuthor
            ? MessageLayout.bubbleContentSpacing
            : 0
        let topInset = showsAuthor
            ? MessageLayout.bubbleVerticalInset
            : MessageLayout.compactSpacing
        let imagesHeight = imageSizes.reduce(CGFloat(0)) { $0 + $1.height }
        let imagesSpacing = CGFloat(max(0, imageSizes.count - 1))
            * MessageLayout.contentItemSpacing
        return ceil(
            imagesHeight
                + imagesSpacing
                + authorHeight
                + authorSpacing
                + topInset
                + MessageLayout.compactSpacing
                + MessageLayout.compactSpacing * 2
        )
    }

    private static func normalizedSourceSizes(_ sourceSizes: [CGSize?]) -> [CGSize?] {
        sourceSizes.isEmpty ? [nil] : sourceSizes
    }

    private static func normalizedSourceSize(_ sourceSize: CGSize?) -> CGSize {
        guard
            let sourceSize,
            sourceSize.width.isFinite,
            sourceSize.height.isFinite,
            sourceSize.width > 0,
            sourceSize.height > 0
        else {
            return CGSize(width: contentWidth, height: contentHeight)
        }

        return sourceSize
    }
}
