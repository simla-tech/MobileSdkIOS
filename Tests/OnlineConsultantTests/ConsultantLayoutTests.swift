import UIKit
import XCTest
@testable import OnlineConsultant

@MainActor
final class ConsultantLayoutTests: XCTestCase {

    func testShortMessageFitsConfiguredManagerNameAfterLayoutAndReuse() throws {
        let config = try JSONDecoder().decode(ConsultantConfig.self, from: Data("""
            {"manager_display_type":"custom","manager_name":"Александра Поддержка"}
            """.utf8))
        let identity = ManagerIdentity(config: config)
        let message = ConsultantMessage(
            content: "Да", user: MessageUser(firstName: "Ян"), fromMe: false, messageType: .text
        )

        for width: CGFloat in [320, 390, 768] {
            let height = MessageCollectionViewCell.preferredHeight(for: message, collectionWidth: width)
            let cell = MessageCollectionViewCell(frame: CGRect(x: 0, y: 0, width: width, height: height))
            for manager in [identity, nil, identity] {
                cell.prepareForReuse()
                cell.configure(message: message, managerIdentity: manager)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                let author = try XCTUnwrap(descendantLabels(in: cell).first {
                    $0.accessibilityIdentifier == "messageAuthorLabel"
                })
                XCTAssertEqual(author.text, manager?.displayName ?? "Ян")
                XCTAssertGreaterThanOrEqual(author.bounds.width + 0.5, author.intrinsicContentSize.width)
            }
        }
    }

    func testManagerNameDoesNotWidenHiddenAuthorOrOutgoingMessages() {
        for outgoing in [false, true] {
            let message = ConsultantMessage(content: "Да", fromMe: outgoing, messageType: .text)
            for showsAuthor in [false, true] where outgoing || !showsAuthor {
                let originalWidth = MessageCollectionViewCell.preferredBubbleWidth(
                    for: message, collectionWidth: 390, showsAuthor: showsAuthor
                )
                let configuredWidth = MessageCollectionViewCell.preferredBubbleWidth(
                    for: message, collectionWidth: 390, showsAuthor: showsAuthor,
                    authorNameOverride: "Александра Поддержка"
                )
                XCTAssertEqual(originalWidth, configuredWidth)
            }
        }
    }

    private func descendantLabels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { child in
            (child as? UILabel).map { [$0] } ?? descendantLabels(in: child)
        }
    }

    func testReusedCellLaysOutOnlyCurrentMessageAtItsMeasuredHeight() throws {
        let messages = [
            ConsultantMessage(content: "Hello", fromMe: false, messageType: .text),
            ConsultantMessage(product: MessageProduct(name: "Product"), fromMe: false, messageType: .product),
            ConsultantMessage(content: "Reply", quoteContent: "Quoted text", fromMe: false, messageType: .text),
            ConsultantMessage(messageType: .contactForm, contactForm: ContactForm(
                text: "Contact us", fields: [.name: ContactFormField(required: true)]
            )),
            ConsultantMessage(content: "OK", fromMe: true, messageType: .text)
        ]
        let bubbleTypes: [UIView.Type] = [
            TextMessageBubbleView.self, ProductMessageBubbleView.self, QuoteMessageBubbleView.self,
            ContactFormMessageBubbleView.self, TextMessageBubbleView.self
        ]

        for width: CGFloat in [320, 390, 768] {
            let cell = MessageCollectionViewCell(frame: CGRect(x: 0, y: 0, width: width, height: 100))
            for (index, message) in messages.enumerated() {
                cell.prepareForReuse()
                let height = MessageCollectionViewCell.preferredHeight(for: message, collectionWidth: width)
                cell.frame.size = CGSize(width: width, height: height)
                cell.configure(message: message)
                cell.layoutIfNeeded()
                let container = try XCTUnwrap(cell.contentView.subviews.first {
                    $0.accessibilityIdentifier == "messageBubbleContainerView"
                })
                XCTAssertEqual(container.subviews.count, 1)
                let bubble = try XCTUnwrap(container.subviews.first)
                XCTAssertTrue(type(of: bubble) == bubbleTypes[index])
                XCTAssertEqual(bubble.frame.width, container.bounds.width, accuracy: 0.5)
                XCTAssertEqual(bubble.frame.height, height - 8, accuracy: 0.5)
                XCTAssertFalse(bubble.isHidden)
            }
        }
    }

    func testChatConfiguredBeforePresentationLaysOutAtContainerSize() throws {
        let view = ConsultantView()
        view.setCanLoadOlderMessages(false)
        view.setMessages([ConsultantMessage(content: "Hello", fromMe: false, messageType: .text)])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        defer { window.isHidden = true }
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.layoutIfNeeded()

        let collection = try XCTUnwrap(view.subviews.flatMap(\.subviews).compactMap { $0 as? UICollectionView }.first)
        collection.layoutIfNeeded()
        XCTAssertEqual(collection.bounds.width, 390, accuracy: 0.5)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        XCTAssertGreaterThan(collection.bounds.height, 0)
        let input = try XCTUnwrap(view.subviews.compactMap { $0 as? InputBar }.first)
        XCTAssertGreaterThan(input.bounds.height, 0)
        XCTAssertEqual(input.frame.maxY, view.safeAreaLayoutGuide.layoutFrame.maxY, accuracy: 0.5)
    }
}
