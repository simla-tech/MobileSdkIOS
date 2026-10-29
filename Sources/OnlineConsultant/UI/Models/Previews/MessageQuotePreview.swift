import Foundation

/// UI-ready preview of the message being quoted.
package enum MessageQuotePreview: Equatable, Sendable {

    /// Text preview displayed inside the quote block.
    case text(String)

    /// Files or images from the quoted message, with its optional text.
    case attachments([MessageItem], isImage: Bool, text: String?, author: String)
}
