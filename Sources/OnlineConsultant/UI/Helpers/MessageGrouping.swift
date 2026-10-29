import Foundation

/// Calculates visual grouping flags for adjacent messages in the chat list.
package enum MessageGrouping {

    /// Returns whether an incoming message should display the sender avatar.
    package static func showsAvatar(
        messages: [ConsultantMessage],
        index: Int
    ) -> Bool {
        guard messages.indices.contains(index) else {
            return false
        }

        let message = messages[index]
        guard message.fromMe != true else {
            return false
        }

        return isLastInSenderGroup(
            messages: messages,
            index: index
        )
    }

    /// Returns whether a message should display the author name above the bubble.
    package static func showsAuthor(
        messages: [ConsultantMessage],
        index: Int
    ) -> Bool {
        guard messages.indices.contains(index) else {
            return false
        }

        return isFirstInSenderGroup(
            messages: messages,
            index: index
        )
    }

    /// Returns whether a message bubble should round all corners instead of joining with the next bubble.
    package static func roundsAllCorners(
        messages: [ConsultantMessage],
        index: Int
    ) -> Bool {
        guard messages.indices.contains(index) else {
            return false
        }

        return !isLastInSenderGroup(
            messages: messages,
            index: index
        )
    }

    /// Returns whether the message starts a consecutive group from the same sender.
    private static func isFirstInSenderGroup(
        messages: [ConsultantMessage],
        index: Int
    ) -> Bool {
        guard messages.indices.contains(index) else {
            return false
        }

        let previousIndex = index - 1
        guard messages.indices.contains(previousIndex) else {
            return true
        }

        return !messages[index].hasSameSender(as: messages[previousIndex])
            || MessageDateSeparator.areOnDifferentDays(messages[index], messages[previousIndex])
    }

    /// Returns whether the message ends a consecutive group from the same sender.
    private static func isLastInSenderGroup(
        messages: [ConsultantMessage],
        index: Int
    ) -> Bool {
        guard messages.indices.contains(index) else {
            return false
        }

        let nextIndex = index + 1
        guard messages.indices.contains(nextIndex) else {
            return true
        }

        return !messages[index].hasSameSender(as: messages[nextIndex])
            || MessageDateSeparator.areOnDifferentDays(messages[index], messages[nextIndex])
    }
}
