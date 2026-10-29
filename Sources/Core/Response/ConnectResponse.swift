/// Credentials subset of the response returned by `POST /api/client/v1/connect`.
package struct ConnectResponse: Decodable, Equatable, Sendable {

    /// Backend server timestamp encoded as the `ts` ISO 8601 string.
    package let timestamp: String?

    /// Current backend user.
    package let user: ConnectedUser

    /// Current backend session.
    package let session: ConnectedSession

    /// Runtime availability flags.
    package let behaviour: ConnectBehaviour?

    /// Creates a connect response credentials subset.
    package init(
        timestamp: String? = nil,
        user: ConnectedUser,
        session: ConnectedSession,
        behaviour: ConnectBehaviour? = nil
    ) {
        self.timestamp = timestamp
        self.user = user
        self.session = session
        self.behaviour = behaviour
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case user
        case session
        case behaviour
    }

    /// Resolved credentials for authorized requests, if both token and session id are present.
    package var credentials: SessionCredentials? {
        guard
            let userToken = user.token,
            let sessionID = session.id?.value
        else {
            return nil
        }

        return SessionCredentials(
            userToken: userToken,
            sessionID: sessionID
        )
    }
}
