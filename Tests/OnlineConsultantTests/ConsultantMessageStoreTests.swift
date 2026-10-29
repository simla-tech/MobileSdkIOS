import XCTest
@testable import OnlineConsultant

final class ConsultantMessageStoreTests: XCTestCase {

    func testRealtimeInsertUpdateAndDelete() {
        var store = MessageStore()

        store.applyRealtimeMessage(message(id: "1", content: "First", status: .sent))
        store.applyRealtimeMessage(message(id: "1", content: "Updated", status: .seen))

        XCTAssertEqual(store.messageCount, 1)
        XCTAssertEqual(store.message(id: "1")?.content, "Updated")
        XCTAssertEqual(store.unreadIncomingMessagesCount, 0)

        store.applyRealtimeMessage(message(id: "1", status: .deleted))

        XCTAssertTrue(store.isEmpty)
    }

    func testMarkIncomingMessagesSeenUpToID() {
        var store = MessageStore()
        store.replaceAll([
            message(id: "1", status: .sent),
            message(id: "2", status: .sent),
            message(id: "3", status: .sent, fromMe: true)
        ])

        XCTAssertTrue(store.markIncomingMessagesSeen(upTo: "2"))
        XCTAssertEqual(store.message(id: "1")?.status, .seen)
        XCTAssertEqual(store.message(id: "2")?.status, .seen)
        XCTAssertEqual(store.message(id: "3")?.status, .sent)
        XCTAssertEqual(store.unreadIncomingMessagesCount, 0)
    }

    func testLocalMessageIsReplacedByAcknowledgement() {
        var store = MessageStore()
        let localID = store.appendLocalOutgoingMessage("Hello")

        XCTAssertEqual(store.message(id: localID)?.status, .sending)

        XCTAssertTrue(store.replaceLocalMessage(
            id: localID,
            sentMessage: ConsultantSentMessage(
                id: "42",
                time: "2026-01-01T00:00:00Z",
                updatedAt: nil,
                status: .sent
            )
        ))
        XCTAssertNil(store.message(id: localID))
        XCTAssertEqual(store.message(id: "42")?.content, "Hello")
    }

    func testUnreadCountTracksLoadedHistoryAndRealtimeChanges() {
        var store = MessageStore()
        XCTAssertEqual(store.unreadIncomingMessagesCount, 0)
        store.replaceAll([message(id: "3", status: .sent)])
        XCTAssertEqual(store.unreadIncomingMessagesCount, 1)

        // Loading an older page counts new messages without double-counting overlapping ids.
        store.merge([
            message(id: "1", status: .sent),
            message(id: "2", status: .sent),
            message(id: "3", status: .sent)
        ])
        XCTAssertEqual(store.unreadIncomingMessagesCount, 3)
        store.applyRealtimeMessage(message(id: "4", status: .sent))
        XCTAssertEqual(store.unreadIncomingMessagesCount, 4)
        store.applyRealtimeMessage(message(id: "4", content: "Updated", status: .sent))
        XCTAssertEqual(store.unreadIncomingMessagesCount, 4)
        store.applyRealtimeMessage(message(id: "4", status: .deleted))
        XCTAssertEqual(store.unreadIncomingMessagesCount, 3)
        XCTAssertTrue(store.markIncomingMessagesSeen(upTo: "2"))
        XCTAssertEqual(store.unreadIncomingMessagesCount, 1)
        store.applyRealtimeMessage(message(id: "3", status: .seen))
        XCTAssertEqual(store.unreadIncomingMessagesCount, 0)
        store.applyRealtimeMessage(message(id: "5", status: .sent))
        store.reset()
        XCTAssertEqual(store.unreadIncomingMessagesCount, 0)
    }

    func testUnreadCountExcludesReadDeletedOutgoingAndVirtualMessages() {
        var store = MessageStore()
        store.replaceAll([
            message(id: "1", status: .seen),
            message(id: "2", status: .deleted),
            message(id: "3", status: .sent, fromMe: true),
            .introMessage(text: "Welcome"),
            message(id: ConsultantMessage.offlineMessageID, status: .sent),
            message(id: "4", status: .sent),
            message(id: "5", status: .sent)
        ])
        XCTAssertEqual(store.unreadIncomingMessagesCount, 2)
    }

    private func message(
        id: String,
        content: String? = nil,
        status: MessageStatus,
        fromMe: Bool = false
    ) -> ConsultantMessage {
        ConsultantMessage(
            id: FlexibleID(id),
            content: content,
            fromMe: fromMe,
            messageType: .text,
            status: status
        )
    }
}
