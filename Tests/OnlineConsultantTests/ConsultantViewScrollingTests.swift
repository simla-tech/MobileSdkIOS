import UIKit
import XCTest
@testable import OnlineConsultant

@MainActor
final class ConsultantViewScrollingTests: XCTestCase {

    func testPendingMessageInsertionDoesNotOverrideManualScroll() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        var messages = makeHistory()
        view.setMessages(messages)
        await finishAnimations()

        messages.append(makeOutgoingMessage(id: "_local_1", status: .sending))
        view.setMessages(messages)
        let offset = scrollToHistory(view: view, collectionView: collectionView)
        await finishAnimations()

        XCTAssertEqual(collectionView.contentOffset.y, offset, accuracy: 1)

        messages[messages.count - 1] = makeOutgoingMessage(id: "100", status: .delivered)
        view.setMessages(messages)
        await finishAnimations()

        XCTAssertEqual(collectionView.contentOffset.y, offset, accuracy: 1)
    }

    func testDeliveryStatusChangesPreserveHistoryPosition() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        var messages = makeHistory() + [makeOutgoingMessage(id: "_local_1", status: .sending)]
        view.setMessages(messages)
        await finishAnimations()
        let offset = scrollToHistory(view: view, collectionView: collectionView)

        for (id, status) in [
            ("_local_1", MessageStatus.sent),
            ("100", .delivered),
            ("100", .seen)
        ] {
            messages[messages.count - 1] = makeOutgoingMessage(id: id, status: status)
            view.setMessages(messages)
            await finishAnimations()

            XCTAssertEqual(collectionView.contentOffset.y, offset, accuracy: 1)
        }
    }

    func testNewMessageAndDeliveryStatusKeepBottomWhenNotScrolling() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        var messages = makeHistory()
        view.setMessages(messages)
        await finishAnimations()

        messages.append(makeOutgoingMessage(id: "_local_1", status: .sending))
        view.setMessages(messages)
        await finishAnimations()
        XCTAssertEqual(collectionView.contentOffset.y, bottomOffset(in: collectionView), accuracy: 1)

        messages[messages.count - 1] = makeOutgoingMessage(id: "100", status: .delivered)
        view.setMessages(messages)
        await finishAnimations()
        XCTAssertEqual(collectionView.contentOffset.y, bottomOffset(in: collectionView), accuracy: 1)
    }

    func testComposerAnimationDoesNotOverrideManualScroll() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        view.setMessages(makeHistory())
        await finishAnimations()

        let inputBar = try XCTUnwrap(view.subviews.compactMap { $0 as? InputBar }.first)
        let textView = try XCTUnwrap(inputBar.subviews.compactMap { $0 as? UITextView }.first)
        textView.text = "First line\nSecond line\nThird line"
        inputBar.textViewDidChange(textView)
        await finishAnimations()

        view.clearMessageInput()
        let offset = scrollToHistory(view: view, collectionView: collectionView)
        await finishAnimations()

        XCTAssertEqual(collectionView.contentOffset.y, offset, accuracy: 1)
    }

    func testImmediateDeliveryStatusUpdateKeepsBottomWhenNotScrolling() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        var messages = makeHistory()
        view.setMessages(messages)
        await finishAnimations()

        let content = Array(repeating: "Outgoing message", count: 8).joined(separator: "\n")
        messages.append(makeOutgoingMessage(id: "_local_1", status: .sending, content: content))
        view.setMessages(messages)
        messages[messages.count - 1] = makeOutgoingMessage(id: "100", status: .delivered, content: content)
        view.setMessages(messages)
        await finishAnimations()

        XCTAssertEqual(collectionView.contentOffset.y, bottomOffset(in: collectionView), accuracy: 1)
    }

    func testKeyboardAnimationDoesNotOverrideManualScroll() async throws {
        let (window, view, collectionView) = try makeChat()
        defer { window.isHidden = true }
        view.setMessages(makeHistory())
        await finishAnimations()

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 544, width: 390, height: 300),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.25
            ]
        )
        let offset = scrollToHistory(view: view, collectionView: collectionView)
        await finishAnimations()

        XCTAssertEqual(collectionView.contentOffset.y, offset, accuracy: 1)
    }

    func testEmptyKeyboardFrameDoesNotLeaveComposerRaisedDuringTransform() async throws {
        let (window, view, _) = try makeChat()
        defer { window.isHidden = true }
        let inputBar = try XCTUnwrap(view.subviews.compactMap { $0 as? InputBar }.first)

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 544, width: 390, height: 300),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0
            ]
        )
        await finishAnimations()
        XCTAssertLessThan(inputBar.frame.maxY, view.safeAreaLayoutGuide.layoutFrame.maxY - 100)

        view.transform = CGAffineTransform(rotationAngle: 0.01).scaledBy(x: 1.001, y: 1.001)
        for frame in [
            CGRect(x: 0, y: 874, width: 402, height: 0),
            CGRect(x: 0, y: 544, width: 402, height: 0)
        ] {
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                userInfo: [
                    UIResponder.keyboardFrameEndUserInfoKey: frame,
                    UIResponder.keyboardAnimationDurationUserInfoKey: 0
                ]
            )
            await finishAnimations()
            XCTAssertEqual(inputBar.frame.maxY, view.safeAreaLayoutGuide.layoutFrame.maxY, accuracy: 0.5)
        }
    }

    private func makeChat() throws -> (UIWindow, ConsultantView, UICollectionView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        let view = ConsultantView(frame: window.bounds)
        view.setCanLoadOlderMessages(false)
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            view.subviews.flatMap(\.subviews).compactMap { $0 as? UICollectionView }.first
        )
        return (window, view, collectionView)
    }

    private func makeHistory() -> [ConsultantMessage] {
        (1...40).map {
            ConsultantMessage(
                id: FlexibleID(String($0)),
                content: "History message \($0)",
                time: "2026-10-20T10:00:00Z",
                fromMe: false,
                messageType: .text,
                status: .seen
            )
        }
    }

    private func makeOutgoingMessage(
        id: String,
        status: MessageStatus,
        content: String = "Outgoing message"
    ) -> ConsultantMessage {
        ConsultantMessage(
            id: FlexibleID(id),
            content: content,
            time: "2026-10-20T10:01:00Z",
            fromMe: true,
            messageType: .text,
            status: status
        )
    }

    private func scrollToHistory(view: ConsultantView, collectionView: UICollectionView) -> CGFloat {
        collectionView.delegate?.scrollViewWillBeginDragging?(collectionView)
        let offset = bottomOffset(in: collectionView) - 300
        collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        // UIKit sets isDragging during a real pan; supply it for the delegate callback.
        view.scrollViewDidScroll(DraggingScrollView())
        collectionView.delegate?.scrollViewDidEndDragging?(collectionView, willDecelerate: false)
        return offset
    }

    private func bottomOffset(in collectionView: UICollectionView) -> CGFloat {
        collectionView.contentSize.height - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
    }

    private func finishAnimations() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

private final class DraggingScrollView: UIScrollView {
    override var isDragging: Bool { true }
}
