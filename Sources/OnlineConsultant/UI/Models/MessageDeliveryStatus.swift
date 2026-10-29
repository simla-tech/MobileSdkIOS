import Foundation

/// UI delivery status used by message metadata and status icons.
package enum MessageDeliveryStatus: Equatable {

    /// No delivery status should be displayed.
    case none

    /// Message is being created or sent.
    case sending

    /// Message has been accepted by backend or transport.
    case delivered

    /// Message has been seen by the recipient.
    case read

    /// Message failed to send.
    case error

    /// Maps backend and local message statuses to UI delivery statuses.
    package init(messageStatus: MessageStatus?) {
        switch messageStatus {
        case nil, .new, .undefined, .sending:
            self = .sending
        case .sent, .delivered:
            self = .delivered
        case .seen:
            self = .read
        case .failed:
            self = .error
        default:
            self = .none
        }
    }
}
