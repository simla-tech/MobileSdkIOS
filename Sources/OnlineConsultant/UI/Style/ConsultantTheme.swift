import UIKit

/// Runtime color theme used by the SDK chat UI.
package struct ConsultantTheme {

    /// Main accent color resolved from the consultant configuration.
    package let brandColor: UIColor

    /// Semi-transparent accent color used for focus, highlights, and subtle backgrounds.
    package let brandAlphaColor: UIColor

    /// Background color for the chat screen.
    package let screenBackgroundColor: UIColor

    /// Background color for the input bar area.
    package let bottomBarColor: UIColor

    /// Background color for incoming consultant message bubbles.
    package let consultantBubbleColor: UIColor

    /// Background color for outgoing visitor message bubbles.
    package let visitorBubbleColor: UIColor

    /// Primary text color used on top of the accent color.
    package let mainTextColor: UIColor

    /// Primary icon tint used on top of the accent color.
    package let mainIconColor: UIColor

    /// Main readable text color for neutral surfaces and incoming bubbles.
    package let primaryTextColor: UIColor

    /// Timestamp and secondary metadata color for incoming messages.
    package let messageDateColor: UIColor

    /// Placeholder text color for inputs and empty UI states.
    package let placeholderTextColor: UIColor

    /// Divider and neutral border color.
    package let dividerColor: UIColor

    /// Background color for text input and form fields.
    package let areaBackgroundColor: UIColor

    /// Text color for text input and form fields.
    package let areaTextColor: UIColor

    /// Icon tint for controls inside input and form areas.
    package let areaIconColor: UIColor

    /// Border color for text input and form fields.
    package let areaBorderColor: UIColor

    /// Whether consultant-controlled elements should use rounded styling.
    package let roundedElements: Bool

    /// Whether the consultant uses the dark background theme.
    package let isDarkTheme: Bool

    /// Default light theme matching the web consultant fallback palette.
    package static let defaultTheme = ConsultantTheme(
        brandColor: UIColor(hex: 0x005EEB),
        brandAlphaColor: UIColor(hex: 0x005EEB, alpha: 0.12),
        screenBackgroundColor: .white,
        bottomBarColor: .white,
        consultantBubbleColor: UIColor(hex: 0xF4F6F8),
        visitorBubbleColor: UIColor(hex: 0x005EEB),
        mainTextColor: .white,
        mainIconColor: .white,
        primaryTextColor: UIColor(hex: 0x1E2248),
        messageDateColor: UIColor(hex: 0x8A96A6),
        placeholderTextColor: UIColor(hex: 0xAFB9C3),
        dividerColor: UIColor(hex: 0xDEE2E6),
        areaBackgroundColor: .white,
        areaTextColor: .black,
        areaIconColor: UIColor(hex: 0x636F7F, alpha: 0.47),
        areaBorderColor: UIColor(hex: 0xDEE2E6),
        roundedElements: true,
        isDarkTheme: false
    )

    /// Dark theme screen background matching the web consultant dark palette.
    private static let darkBackgroundColor = UIColor(hex: 0x0A0A0A)

    /// Creates a theme from backend consultant config or falls back to the default theme.
    package init(config: ConsultantConfig?) {
        guard let config else {
            self = Self.defaultTheme
            return
        }

        let defaultTheme = Self.defaultTheme
        let brandColor = UIColor(hexString: config.elementsColor) ?? defaultTheme.brandColor
        let mainTextColor = config.inverse ? defaultTheme.primaryTextColor : defaultTheme.mainTextColor
        let darkTheme = config.isDarkBackground

        self.init(
            brandColor: brandColor,
            brandAlphaColor: brandColor.withAlphaComponent(0.12),
            screenBackgroundColor: darkTheme ? Self.darkBackgroundColor : defaultTheme.screenBackgroundColor,
            bottomBarColor: darkTheme ? Self.darkBackgroundColor : defaultTheme.bottomBarColor,
            consultantBubbleColor: darkTheme
                ? defaultTheme.mainTextColor.withAlphaComponent(0.10)
                : defaultTheme.consultantBubbleColor,
            visitorBubbleColor: brandColor,
            mainTextColor: mainTextColor,
            mainIconColor: mainTextColor,
            primaryTextColor: darkTheme ? defaultTheme.mainTextColor : defaultTheme.primaryTextColor,
            messageDateColor: darkTheme ? defaultTheme.placeholderTextColor : defaultTheme.messageDateColor,
            placeholderTextColor: defaultTheme.placeholderTextColor,
            dividerColor: darkTheme ? .clear : defaultTheme.dividerColor,
            areaBackgroundColor: darkTheme
                ? defaultTheme.mainTextColor.withAlphaComponent(0.10)
                : defaultTheme.areaBackgroundColor,
            areaTextColor: darkTheme ? defaultTheme.mainTextColor : defaultTheme.areaTextColor,
            areaIconColor: darkTheme
                ? defaultTheme.mainTextColor.withAlphaComponent(0.40)
                : defaultTheme.areaIconColor,
            areaBorderColor: darkTheme
                ? defaultTheme.mainTextColor.withAlphaComponent(0.10)
                : defaultTheme.areaBorderColor,
            roundedElements: config.roundedElements,
            isDarkTheme: darkTheme
        )
    }

    /// Creates a fully resolved theme without consulting backend configuration.
    private init(
        brandColor: UIColor,
        brandAlphaColor: UIColor,
        screenBackgroundColor: UIColor,
        bottomBarColor: UIColor,
        consultantBubbleColor: UIColor,
        visitorBubbleColor: UIColor,
        mainTextColor: UIColor,
        mainIconColor: UIColor,
        primaryTextColor: UIColor,
        messageDateColor: UIColor,
        placeholderTextColor: UIColor,
        dividerColor: UIColor,
        areaBackgroundColor: UIColor,
        areaTextColor: UIColor,
        areaIconColor: UIColor,
        areaBorderColor: UIColor,
        roundedElements: Bool,
        isDarkTheme: Bool
    ) {
        self.brandColor = brandColor
        self.brandAlphaColor = brandAlphaColor
        self.screenBackgroundColor = screenBackgroundColor
        self.bottomBarColor = bottomBarColor
        self.consultantBubbleColor = consultantBubbleColor
        self.visitorBubbleColor = visitorBubbleColor
        self.mainTextColor = mainTextColor
        self.mainIconColor = mainIconColor
        self.primaryTextColor = primaryTextColor
        self.messageDateColor = messageDateColor
        self.placeholderTextColor = placeholderTextColor
        self.dividerColor = dividerColor
        self.areaBackgroundColor = areaBackgroundColor
        self.areaTextColor = areaTextColor
        self.areaIconColor = areaIconColor
        self.areaBorderColor = areaBorderColor
        self.roundedElements = roundedElements
        self.isDarkTheme = isDarkTheme
    }
}
