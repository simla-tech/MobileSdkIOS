import Foundation

/// Calendar-day boundaries and localized labels for the chat timeline.
package enum MessageDateSeparator {
    package static func date(
        messages: [ConsultantMessage],
        index: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard messages.indices.contains(index),
              let value = messages[index].time,
              let date = DateParser.date(from: value) else { return nil }

        if index > 0,
           let previousValue = messages[index - 1].time,
           let previousDate = DateParser.date(from: previousValue),
           calendar.isDate(date, inSameDayAs: previousDate) {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    package static func areOnDifferentDays(_ first: ConsultantMessage, _ second: ConsultantMessage) -> Bool {
        guard let firstValue = first.time, let secondValue = second.time,
              let firstDate = DateParser.date(from: firstValue),
              let secondDate = DateParser.date(from: secondValue) else { return false }
        return !Calendar.autoupdatingCurrent.isDate(firstDate, inSameDayAs: secondDate)
    }

    package static func text(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: Bundle.module.preferredLocalizations.first ?? "ru")
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return ConsultantLocalization.messageDateToday.localized
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return ConsultantLocalization.messageDateYesterday.localized
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? ConsultantLocalization.messageDateFormat.localized
            : ConsultantLocalization.messageDateYearFormat.localized
        return formatter.string(from: date)
    }
}
