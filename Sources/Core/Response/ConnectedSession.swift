/// The session object returned by `POST /connect`.
package struct ConnectedSession: Decodable, Equatable, Sendable {

    /// Backend session identifier used as `X-Session-Id` after connect.
    package let id: SessionID?

    /// Creates a connected session value.
    package init(id: SessionID? = nil) {
        self.id = id
    }
}
