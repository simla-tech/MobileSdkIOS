/// Backend session identifier returned by `POST /connect`.
package struct SessionID: Decodable, Equatable, Sendable {

    /// String representation of `session.id`.
    package let value: String

    /// Creates a session id from a string value.
    package init(value: String) {
        self.value = value
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
            return
        }
        if let intValue = try? container.decode(Int64.self) {
            value = String(intValue)
            return
        }

        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string or integer session id"
            )
        )
    }
}
