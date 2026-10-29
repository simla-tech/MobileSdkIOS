//
//  Array.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

package extension Array where Element == ConsultantMessage {

    func sortedForChatDisplay() -> [ConsultantMessage] {
        let indexedMessages = enumerated()
        let realMessages = indexedMessages.filter { !$0.element.isVirtualSupportMessage }
        let virtualSupportMessages = indexedMessages.filter { $0.element.isVirtualSupportMessage }

        return realMessages
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.chatSortDate
                let rhsDate = rhs.element.chatSortDate

                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.offset < rhs.offset
                    }

                    return lhsDate < rhsDate
                case (.some, nil):
                    return false
                case (nil, .some):
                    return true
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
            + virtualSupportMessages.map(\.element)
    }

    var containsVisitorMessage: Bool {
        contains { message in
            message.fromMe == true && message.contactForm == nil
        }
    }
}
