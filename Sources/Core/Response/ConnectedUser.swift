/// The user object returned by `POST /connect`.
package struct ConnectedUser: Decodable, Equatable, Sendable {

    /// User token used as `X-User-Token` after connect.
    package let token: String?

    /// User display name returned by the backend.
    package let name: String?

    /// User email returned by the backend.
    package let email: String?

    /// User phone returned by the backend.
    package let phone: String?

    /// Creates a connected user value.
    package init(
        token: String? = nil,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.token = token
        self.name = name
        self.email = email
        self.phone = phone
    }
}
