//
//  String.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

package extension String {

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

package extension String {

    var weekdayNumber: Int? {
        switch trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sun":
            return 0
        case "mon":
            return 1
        case "tue":
            return 2
        case "wed":
            return 3
        case "thu":
            return 4
        case "fri":
            return 5
        case "sat":
            return 6
        default:
            return nil
        }
    }

    var timeMinutes: Int? {
        let components = trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard
            components.count >= 2,
            let hour = Int(components[0]),
            let minute = Int(components[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }

        return hour * 60 + minute
    }
}
