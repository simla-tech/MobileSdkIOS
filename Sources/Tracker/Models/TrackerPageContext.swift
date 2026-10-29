import Core
import Foundation

package struct TrackerPageContext: Equatable, Sendable {
    package let pageURL: String
    package let pageTitle: String?
    package let referrerURL: String?

    package init(
        pageURL: String,
        pageTitle: String? = nil,
        referrerURL: String? = nil
    ) {
        self.pageURL = pageURL
        self.pageTitle = pageTitle?.nilIfEmpty
        self.referrerURL = referrerURL?.nilIfEmpty
    }
}
