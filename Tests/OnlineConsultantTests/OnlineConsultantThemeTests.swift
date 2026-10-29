import UIKit
import XCTest
@testable import OnlineConsultant

final class ConsultantThemeTests: XCTestCase {

    func testThemeUsesDefaultLightPaletteWithoutConfig() {
        let theme = ConsultantTheme(config: nil)

        assertColor(theme.brandColor, red: 0, green: 94, blue: 235)
        assertColor(theme.brandAlphaColor, red: 0, green: 94, blue: 235, alpha: 0.12)
        assertColor(theme.screenBackgroundColor, red: 255, green: 255, blue: 255)
        assertColor(theme.consultantBubbleColor, red: 244, green: 246, blue: 248)
        assertColor(theme.visitorBubbleColor, red: 0, green: 94, blue: 235)
        assertColor(theme.mainTextColor, red: 255, green: 255, blue: 255)
        assertColor(theme.primaryTextColor, red: 30, green: 34, blue: 72)
        assertColor(theme.areaIconColor, red: 99, green: 111, blue: 127, alpha: 0.47)
        XCTAssertEqual(theme.roundedElements, true)
    }

    func testThemeBuildsColorsFromBackendVisualConfig() throws {
        let config = try JSONDecoder().decode(
            ConsultantConfig.self,
            from: Data(
                """
                {
                  "elements_color": "FF5500",
                  "bg_color": "dark",
                  "inverse": true,
                  "element_shape": "rectangular form"
                }
                """.utf8
            )
        )

        let theme = ConsultantTheme(config: config)

        assertColor(theme.brandColor, red: 255, green: 85, blue: 0)
        assertColor(theme.brandAlphaColor, red: 255, green: 85, blue: 0, alpha: 0.12)
        assertColor(theme.screenBackgroundColor, red: 10, green: 10, blue: 10)
        assertColor(theme.bottomBarColor, red: 10, green: 10, blue: 10)
        assertColor(theme.consultantBubbleColor, red: 255, green: 255, blue: 255, alpha: 0.10)
        assertColor(theme.visitorBubbleColor, red: 255, green: 85, blue: 0)
        assertColor(theme.mainTextColor, red: 30, green: 34, blue: 72)
        assertColor(theme.mainIconColor, red: 30, green: 34, blue: 72)
        assertColor(theme.primaryTextColor, red: 255, green: 255, blue: 255)
        assertColor(theme.messageDateColor, red: 175, green: 185, blue: 195)
        assertColor(theme.dividerColor, red: 0, green: 0, blue: 0, alpha: 0)
        assertColor(theme.areaBackgroundColor, red: 255, green: 255, blue: 255, alpha: 0.10)
        assertColor(theme.areaTextColor, red: 255, green: 255, blue: 255)
        assertColor(theme.areaBorderColor, red: 255, green: 255, blue: 255, alpha: 0.10)
        XCTAssertEqual(theme.roundedElements, false)
    }

    func testThemeFallsBackToDefaultBrandColorWhenConfigColorIsInvalid() throws {
        let config = try JSONDecoder().decode(
            ConsultantConfig.self,
            from: Data(#"{ "elements_color": "not-a-color" }"#.utf8)
        )

        let theme = ConsultantTheme(config: config)

        assertColor(theme.brandColor, red: 0, green: 94, blue: 235)
        assertColor(theme.visitorBubbleColor, red: 0, green: 94, blue: 235)
    }

    func testMessageBubbleStyleUsesThemeColors() throws {
        let theme = try makeTheme(
            """
            {
              "elements_color": "FF5500",
              "bg_color": "dark",
              "inverse": true
            }
            """
        )

        assertColor(
            MessageBubbleStyle.bubbleColor(isOutgoing: true, theme: theme),
            red: 255,
            green: 85,
            blue: 0
        )
        assertColor(
            MessageBubbleStyle.bubbleColor(isOutgoing: false, theme: theme),
            red: 255,
            green: 255,
            blue: 255,
            alpha: 0.10
        )
        assertColor(
            MessageBubbleStyle.textColor(isOutgoing: true, theme: theme),
            red: 30,
            green: 34,
            blue: 72
        )
        assertColor(
            MessageBubbleStyle.textColor(isOutgoing: false, theme: theme),
            red: 255,
            green: 255,
            blue: 255
        )
    }

    @MainActor
    func testConsultantViewAppliesBackendThemeToRootAndInputBar() throws {
        let config = try decodeConfig(
            """
            {
              "elements_color": "FF5500",
              "bg_color": "dark",
              "inverse": true,
              "element_shape": "rectangular form"
            }
            """
        )
        let view = ConsultantView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        view.setConsultantConfig(config)
        view.layoutIfNeeded()

        let textView = try XCTUnwrap(
            view.recursiveSubviews()
                .compactMap { $0 as? UITextView }
                .first { $0.accessibilityIdentifier == "messageInputTextView" }
        )
        let sendButton = try XCTUnwrap(
            view.recursiveSubviews()
                .compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "sendMessageButton" }
        )

        assertColor(view.backgroundColor ?? .clear, red: 10, green: 10, blue: 10)
        assertColor(textView.backgroundColor ?? .clear, red: 255, green: 255, blue: 255, alpha: 0.10)
        assertColor(textView.textColor ?? .clear, red: 255, green: 255, blue: 255)
        assertColor(sendButton.backgroundColor ?? .clear, red: 99, green: 111, blue: 127, alpha: 0.20)
        assertColor(sendButton.tintColor, red: 30, green: 34, blue: 72)
        XCTAssertFalse(sendButton.isEnabled)
        XCTAssertFalse(sendButton.adjustsImageWhenDisabled)
        XCTAssertEqual(textView.layer.cornerRadius, 4)
        XCTAssertEqual(sendButton.layer.cornerRadius, 4)
    }

    @MainActor
    func testConsultantViewPassesBackendThemeAndManagerIdentityToMessageCells() throws {
        let config = try decodeConfig(
            """
            {
              "elements_color": "FF5500",
              "element_shape": "rectangular form",
              "manager_display_type": "custom",
              "manager_name": "Анна Поддержка"
            }
            """
        )
        let view = ConsultantView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let incomingMessage = ConsultantMessage(
            id: FlexibleID("message-1"),
            content: "Добрый день",
            time: "2026-06-30T09:35:00Z",
            user: MessageUser(firstName: "Евгений", lastName: "Петровский"),
            fromMe: false,
            messageType: "text",
            status: "sent"
        )
        let outgoingMessage = ConsultantMessage(
            id: FlexibleID("message-2"),
            content: "Здравствуйте",
            time: "2026-06-30T09:36:00Z",
            fromMe: true,
            messageType: "text",
            status: "sent"
        )

        view.setConsultantConfig(config)
        view.setMessages([incomingMessage, outgoingMessage])
        view.layoutIfNeeded()
        drainMainRunLoop()

        let collectionView = try XCTUnwrap(view.messagesCollectionViewForTests())
        let incomingCell = try XCTUnwrap(
            collectionView.dataSource?.collectionView(
                collectionView,
                cellForItemAt: IndexPath(item: 0, section: 0)
            ) as? MessageCollectionViewCell
        )
        let outgoingCell = try XCTUnwrap(
            collectionView.dataSource?.collectionView(
                collectionView,
                cellForItemAt: IndexPath(item: 1, section: 0)
            ) as? MessageCollectionViewCell
        )
        incomingCell.layoutIfNeeded()
        outgoingCell.layoutIfNeeded()

        let authorLabel = incomingCell.contentView
            .recursiveSubviews()
            .compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "messageAuthorLabel" }
        let outgoingBubbleView = outgoingCell.contentView
            .recursiveSubviews()
            .compactMap { $0 as? MessageBubbleView }
            .first

        XCTAssertEqual(authorLabel?.text, "Анна Поддержка")
        assertColor(outgoingBubbleView?.backgroundColor ?? .clear, red: 255, green: 85, blue: 0)
        XCTAssertEqual(outgoingBubbleView?.layer.cornerRadius, 4)
    }
}

private func makeTheme(_ json: String) throws -> ConsultantTheme {
    let config = try decodeConfig(json)
    return ConsultantTheme(config: config)
}

private func decodeConfig(_ json: String) throws -> ConsultantConfig {
    try JSONDecoder().decode(
        ConsultantConfig.self,
        from: Data(json.utf8)
    )
}

private func assertColor(
    _ color: UIColor,
    red expectedRed: CGFloat,
    green expectedGreen: CGFloat,
    blue expectedBlue: CGFloat,
    alpha expectedAlpha: CGFloat = 1,
    accuracy: CGFloat = 0.002,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
    XCTAssertEqual(red, expectedRed / 255, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(green, expectedGreen / 255, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(blue, expectedBlue / 255, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(alpha, expectedAlpha, accuracy: accuracy, file: file, line: line)
}

private func drainMainRunLoop() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

private extension UIView {

    func recursiveSubviews() -> [UIView] {
        subviews + subviews.flatMap { $0.recursiveSubviews() }
    }
}

private extension ConsultantView {

    func messagesCollectionViewForTests() -> UICollectionView? {
        recursiveSubviews().compactMap { $0 as? UICollectionView }.first
    }
}
