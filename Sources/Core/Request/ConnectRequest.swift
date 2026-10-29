/// The request body sent to `POST /api/client/v1/connect`.
package struct ConnectRequest: Encodable, Equatable, Sendable {

    /// User data used to restore an existing user or create a new one.
    package let user: ConnectUser

    /// Current page or screen title encoded as `page_title`.
    package let pageTitle: String?

    /// Current page URL used for tracker event filtering.
    package let url: String?

    /// Current page URL encoded as `refer_url` for backend session metadata.
    package let referURL: String?

    /// Creates a connect request from user identity data and page context metadata.
    package init(
        user: ConnectUser = ConnectUser(),
        pageContext: ConnectPageContext = ConnectPageContext()
    ) {
        self.user = user
        self.pageTitle = pageContext.title
        self.url = pageContext.url?.absoluteString
        self.referURL = pageContext.referURL?.absoluteString
    }

    private enum CodingKeys: String, CodingKey {
        case user
        case pageTitle = "page_title"
        case url
        case referURL = "refer_url"
    }
}
