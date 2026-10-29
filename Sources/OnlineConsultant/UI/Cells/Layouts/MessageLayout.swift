import UIKit

/// Shared message layout metrics used by all chat bubble types.
package enum MessageLayout {

    /// Maximum bubble width as a fraction of the available collection width.
    package static let bubbleMaxWidthMultiplier: CGFloat = 0.8
    /// Default horizontal content inset inside a bubble.
    package static let bubbleHorizontalInset: CGFloat = 10
    /// Default vertical content inset inside a bubble.
    package static let bubbleVerticalInset: CGFloat = 10
    /// Default spacing between primary arranged content blocks inside a bubble.
    package static let bubbleContentSpacing: CGFloat = 10
    /// Default line height for primary content text.
    package static let contentLineHeight: CGFloat = 20
    /// Default line height for secondary text such as author, metadata, and file size.
    package static let secondaryLineHeight: CGFloat = 16
    /// Default spacing between closely related content items.
    package static let contentItemSpacing: CGFloat = 8
    /// Compact spacing used for small insets and tightly grouped elements.
    package static let compactSpacing: CGFloat = 4
    /// Default corner radius for framed bubble content.
    package static let contentCornerRadius: CGFloat = 8
    /// Smaller corner radius used when rounded elements are disabled.
    package static let compactCornerRadius: CGFloat = 4
    /// Minimum message cell height used to keep very small messages tappable and stable.
    package static let minimumCellHeight: CGFloat = 52
    /// Fallback height for embedded images when a source size is unavailable.
    package static let embeddedImageFallbackHeight: CGFloat = 128
}
