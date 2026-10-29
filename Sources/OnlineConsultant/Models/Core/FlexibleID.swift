import Foundation

/// Identifier wrapper that accepts backend IDs encoded as either strings or numbers.
///
/// The SDK normalizes every decoded identifier to a string so UI, caching, and comparisons can use
/// one stable representation even when backend payloads are not type-consistent.
package struct FlexibleID: Codable, Equatable, Hashable, Sendable {

    /// Normalized string value of the identifier.
    package let value: String

    /// Creates an identifier from an already normalized string value.
    package init(_ value: String) {
        self.value = value
    }

    /// Decodes a string or numeric JSON value and stores it as a string.
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self.value = value
            return
        }

        if let value = try? container.decode(Int.self) {
            self.value = String(value)
            return
        }

        if let value = try? container.decode(Int64.self) {
            self.value = String(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self.value = String(value)
            return
        }

        throw DecodingError.typeMismatch(
            FlexibleID.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string or numeric id"
            )
        )
    }

    /// Encodes the identifier as a string value.
    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
