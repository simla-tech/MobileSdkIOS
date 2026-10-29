import CoreGraphics

/// Measures contact form message bubbles.
package enum ContactFormMessageLayout {

    /// Default form content width used as the upper bound for bubble measurement.
    package static let defaultContentWidth: CGFloat = 312

    /// Returns the preferred contact form bubble width constrained by the maximum bubble width.
    package static func preferredBubbleWidth(maxBubbleWidth: CGFloat) -> CGFloat {
        min(maxBubbleWidth, defaultContentWidth + MessageLayout.bubbleHorizontalInset * 2)
    }

    /// Returns the full cell height for a contact form message.
    package static func preferredHeight(
        formHeight: CGFloat
    ) -> CGFloat {
        ceil(MessageLayout.bubbleVerticalInset * 2
            + formHeight
            + MessageLayout.compactSpacing * 2)
    }
}
