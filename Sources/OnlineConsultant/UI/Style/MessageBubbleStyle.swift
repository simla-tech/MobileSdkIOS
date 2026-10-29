import UIKit

/// Shared visual tokens used by message bubble views.
package enum MessageBubbleStyle {

    /// Default text color for bubble content that is not driven by the runtime theme.
    package static let textColor = UIColor(red: 30 / 255, green: 34 / 255, blue: 72 / 255, alpha: 1.0)

    /// Background color for image or file placeholders.
    package static let placeholderBackgroundColor = UIColor(red: 222 / 255, green: 226 / 255, blue: 230 / 255, alpha: 1)

    /// Tint color for placeholder icons.
    package static let placeholderIconColor = UIColor(red: 138 / 255, green: 150 / 255, blue: 166 / 255, alpha: 1)

    /// Color used for positive stock or payment states.
    package static let inStockColor = UIColor(red: 32 / 255, green: 167 / 255, blue: 127 / 255, alpha: 1)

    /// Color used for negative stock or payment states.
    package static let outOfStockColor = UIColor(red: 221 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)

    /// Accent color for the leading bar in quote previews.
    package static let quoteBarColor = UIColor(red: 175 / 255, green: 185 / 255, blue: 195 / 255, alpha: 1)

    /// Text color for quoted message previews.
    package static let quoteTextColor = UIColor(red: 138 / 255, green: 150 / 255, blue: 166 / 255, alpha: 1)

    /// Font used for author names above incoming bubbles.
    package static let authorFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

    /// Regular 13pt font used for compact secondary labels.
    package static let regularSmallFont = UIFont.systemFont(ofSize: 13, weight: .regular)

    /// Regular 14pt font used for compact body labels.
    package static let regularCompactFont = UIFont.systemFont(ofSize: 14, weight: .regular)

    /// Semibold 14pt font used for compact emphasized labels.
    package static let semiboldCompactFont = UIFont.systemFont(ofSize: 14, weight: .semibold)

    /// Semibold 15pt font used for medium emphasis.
    package static let semiboldMediumFont = UIFont.systemFont(ofSize: 15, weight: .semibold)

    /// Default body font for text message content.
    package static let messageFont = UIFont.systemFont(ofSize: 17, weight: .regular)

    /// Semibold 17pt font used for large emphasized text.
    package static let semiboldLargeFont = UIFont.systemFont(ofSize: 17, weight: .semibold)

    /// Font used for message timestamps and delivery metadata.
    package static let metadataFont = UIFont.systemFont(ofSize: 11, weight: .regular)

    /// Returns the readable text color for an incoming or outgoing bubble.
    package static func textColor(
        isOutgoing: Bool,
        theme: ConsultantTheme
    ) -> UIColor {
        isOutgoing ? theme.mainTextColor : theme.primaryTextColor
    }

    /// Returns the secondary text color for an incoming or outgoing bubble.
    package static func secondaryColor(
        isOutgoing: Bool,
        theme: ConsultantTheme
    ) -> UIColor {
        isOutgoing ? theme.mainTextColor.withAlphaComponent(0.74) : theme.messageDateColor
    }

    /// Returns the background color for an incoming or outgoing bubble.
    package static func bubbleColor(
        isOutgoing: Bool,
        theme: ConsultantTheme
    ) -> UIColor {
        isOutgoing ? theme.visitorBubbleColor : theme.consultantBubbleColor
    }
}
