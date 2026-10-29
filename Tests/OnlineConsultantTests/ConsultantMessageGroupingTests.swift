import XCTest
@testable import OnlineConsultant

final class ConsultantMessageGroupingTests: XCTestCase {

    func testIncomingSenderGroup() {
        for count in [2, 3] {
            let messages = (0..<count).map { incomingMessage(firstName: "Юрий", lastName: "Девятаев", content: "Message \($0)") }
                + [outgoingMessage(content: "Ответ")]
            assertGrouping(messages, avatars: Array(repeating: false, count: count - 1) + [true, false],
                           authors: [true] + Array(repeating: false, count: count - 1) + [true],
                           corners: Array(repeating: true, count: count - 1) + [false, false])
        }
    }

    func testOutgoingSenderGroup() {
        let outgoing = [outgoingMessage(content: "Первое"), outgoingMessage(content: "Второе")]
        assertGrouping(outgoing, avatars: [false, false], authors: [true, false], corners: [true, false])
        assertGrouping(outgoing + [incomingMessage(firstName: "Юрий", lastName: "Девятаев", content: "Ответ")],
                       avatars: [false, false, true], authors: [true, false, true], corners: [true, false, false])
    }

    func testDifferentSendersStartSeparateGroups() {
        let messages = [incomingMessage(firstName: "Юрий", lastName: "Девятаев", content: "Первое"),
                        incomingMessage(firstName: "Евгений", lastName: "Петровский", content: "Второе")]
        assertGrouping(messages, avatars: [true, true], authors: [true, true], corners: [false, false])
    }

    func testIntroMessageShowsAvatarAndAuthorAsBotMessage() {
        assertGrouping([.introMessage(text: "Добро пожаловать")], avatars: [true], authors: [true], corners: [false])
    }

    func testInvalidIndexHasNoGroupingFlags() {
        XCTAssertFalse(MessageGrouping.showsAvatar(messages: [], index: 0))
        XCTAssertFalse(MessageGrouping.showsAuthor(messages: [], index: 0))
        XCTAssertFalse(MessageGrouping.roundsAllCorners(messages: [], index: 0))
    }

    private func assertGrouping(
        _ messages: [ConsultantMessage], avatars: [Bool], authors: [Bool], corners: [Bool],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(messages.indices.map { MessageGrouping.showsAvatar(messages: messages, index: $0) }, avatars, file: file, line: line)
        XCTAssertEqual(messages.indices.map { MessageGrouping.showsAuthor(messages: messages, index: $0) }, authors, file: file, line: line)
        XCTAssertEqual(messages.indices.map { MessageGrouping.roundsAllCorners(messages: messages, index: $0) }, corners, file: file, line: line)
    }

    private func incomingMessage(
        firstName: String,
        lastName: String,
        content: String
    ) -> ConsultantMessage {
        ConsultantMessage(
            content: content,
            user: MessageUser(firstName: firstName, lastName: lastName),
            fromMe: false,
            messageType: "text",
            status: "sent"
        )
    }

    private func outgoingMessage(content: String) -> ConsultantMessage {
        ConsultantMessage(
            content: content,
            fromMe: true,
            messageType: "text",
            status: "sent"
        )
    }
}
