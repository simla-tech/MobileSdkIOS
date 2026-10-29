import UIKit
import XCTest
@testable import OnlineConsultant

final class ConsultantMessageDateSeparatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }

    func testCalendarDayBoundariesUseLocalTime() throws {
        let messages = [
            message("2026-09-01T16:59:59Z"),
            message("2026-09-01T17:00:00Z"),
            message("2026-09-02T10:00:00.123456Z")
        ]
        XCTAssertNotNil(MessageDateSeparator.date(messages: messages, index: 0, calendar: calendar))
        XCTAssertNotNil(MessageDateSeparator.date(messages: messages, index: 1, calendar: calendar))
        XCTAssertNil(MessageDateSeparator.date(messages: messages, index: 2, calendar: calendar))
    }

    func testMissingAndInvalidDatesDoNotProduceLabels() {
        let messages = [message(nil), message("invalid"), message("2026-09-02T10:00:00Z")]
        XCTAssertNil(MessageDateSeparator.date(messages: messages, index: 0))
        XCTAssertNil(MessageDateSeparator.date(messages: messages, index: 1))
        XCTAssertNotNil(MessageDateSeparator.date(messages: messages, index: 2))
        XCTAssertNil(MessageDateSeparator.date(messages: messages, index: 3))
    }

    func testRelativeDatesTakePrecedenceAcrossYearBoundary() throws {
        let now = try XCTUnwrap(DateParser.date(from: "2026-01-01T01:00:00+07:00"))
        let yesterday = try XCTUnwrap(DateParser.date(from: "2025-12-31T10:00:00+07:00"))
        XCTAssertEqual(MessageDateSeparator.text(for: now, now: now, calendar: calendar),
                       ConsultantLocalization.messageDateToday.localized)
        XCTAssertEqual(MessageDateSeparator.text(for: yesterday, now: now, calendar: calendar),
                       ConsultantLocalization.messageDateYesterday.localized)
    }

    func testOlderDatesIncludeYearOnlyOutsideCurrentYear() throws {
        let now = try XCTUnwrap(DateParser.date(from: "2026-10-28T10:00:00Z"))
        for (timestamp, format) in [
            ("2026-09-02T10:00:00Z", ConsultantLocalization.messageDateFormat),
            ("2025-09-02T10:00:00Z", ConsultantLocalization.messageDateYearFormat)
        ] {
            let date = try XCTUnwrap(DateParser.date(from: timestamp))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format.localized
            XCTAssertEqual(MessageDateSeparator.text(for: date, now: now, calendar: calendar,
                                                     locale: Locale(identifier: "ru")),
                           formatter.string(from: date))
        }
    }

    func testSenderGroupBreaksAtDateBoundary() {
        let messages = [message("2026-09-01T10:00:00Z"), message("2026-09-03T10:00:00Z")]
        XCTAssertTrue(MessageGrouping.showsAuthor(messages: messages, index: 1))
        XCTAssertTrue(MessageGrouping.showsAvatar(messages: messages, index: 0))
        XCTAssertFalse(MessageGrouping.roundsAllCorners(messages: messages, index: 0))
    }

    @MainActor
    func testDateLabelLayoutAndReuse() throws {
        let message = message("2026-09-02T10:00:00Z")
        let height = MessageCollectionViewCell.preferredHeight(for: message, collectionWidth: 390)
        let cell = MessageCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 390,
                                                           height: height + MessageCollectionViewCell.dateSeparatorHeight))
        cell.configure(message: message, dateSeparatorText: "2 сентября")
        cell.layoutIfNeeded()
        let label = try XCTUnwrap(cell.contentView.subviews.first {
            $0.accessibilityIdentifier == "messageDateSeparatorLabel"
        } as? UILabel)
        let bubble = try XCTUnwrap(cell.contentView.subviews.first {
            $0.accessibilityIdentifier == "messageBubbleContainerView"
        })
        XCTAssertEqual(label.text, "2 сентября")
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(label.center.x, 195, accuracy: 0.5)
        XCTAssertLessThan(label.frame.maxY, bubble.frame.minY)
        XCTAssertFalse(cell.contentView.hasAmbiguousLayout)

        cell.prepareForReuse()
        cell.frame.size.height = height
        cell.configure(message: message)
        cell.layoutIfNeeded()
        XCTAssertTrue(label.isHidden)
        XCTAssertNil(label.text)
        XCTAssertEqual(bubble.frame.minY, 4, accuracy: 0.5)
    }

    private func message(_ time: String?) -> ConsultantMessage {
        ConsultantMessage(content: "Сообщение", time: time, user: MessageUser(firstName: "Анна"),
                          fromMe: false, messageType: .text, status: .sent)
    }
}
