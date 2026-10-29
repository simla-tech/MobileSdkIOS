/// Credentials used for authorized requests after a successful connect.
package struct SessionCredentials: Equatable, Sendable {

    /// Value for the `X-User-Token` header.
    package let userToken: String

    /// Value for the `X-Session-Id` header.
    package let sessionID: String

    /// Creates credentials for authorized client API requests.
    package init(
        userToken: String,
        sessionID: String
    ) {
        self.userToken = userToken
        self.sessionID = sessionID
    }
}
