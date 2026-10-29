/// User identity and optional contact data sent in the `user` object of `POST /connect`.
package struct ConnectUser: Codable, Equatable, Sendable {

    /// Previously issued user token returned by the backend.
    package let token: String?

    /// Preferred user language, for example `ru`, `en`, or `en-US`.
    package let language: String?

    /// User display name.
    package let name: String?

    /// User phone number.
    package let phone: String?

    /// User email address.
    package let email: String?

    /// Creates user data for the connect request.
    package init(
        token: String? = nil,
        language: String? = nil,
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil
    ) {
        self.token = token
        self.language = language
        self.name = name
        self.phone = phone
        self.email = email
    }

    /// Returns a copy with the provided token.
    package func withToken(_ token: String?) -> ConnectUser {
        ConnectUser(
            token: token,
            language: language,
            name: name,
            phone: phone,
            email: email
        )
    }
}
