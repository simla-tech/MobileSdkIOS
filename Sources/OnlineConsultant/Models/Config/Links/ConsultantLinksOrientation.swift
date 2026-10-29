/// Known layout orientations returned in `config.links_orientation`.
public enum ConsultantLinksOrientation: Codable, Equatable, Sendable, ExpressibleByStringLiteral {

    /// Vertical web widget links layout.
    case vertical

    /// Horizontal web widget links layout.
    case horizontal

    /// Links orientation that is not known by this SDK version.
    case unknown(String)

    /// String value used in backend JSON payloads.
    public var rawValue: String {
        switch self {
        case .vertical:
            return "vertical"
        case .horizontal:
            return "horizontal"
        case .unknown(let value):
            return value
        }
    }

    /// Creates a links orientation from a backend string value.
    ///
    /// - Parameters:
    ///   - rawValue: Value received from the consultant backend.
    public init(rawValue: String) {
        switch rawValue {
        case "vertical":
            self = .vertical
        case "horizontal":
            self = .horizontal
        default:
            self = .unknown(rawValue)
        }
    }

    /// Creates a consultant links orientation from a string literal.
    ///
    /// - Parameters:
    ///   - value: String literal representing a backend value.
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    /// Decodes a `ConsultantLinksOrientation` value from its serialized representation.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            self.init(rawValue: try container.decode(String.self))
        } catch {
            throw ConsultantError.from(error)
        }
    }

    /// Encodes this `ConsultantLinksOrientation` value for serialization.
    ///
    /// - Parameters:
    ///   - encoder: Encoder receiving this value.
    public func encode(to encoder: Encoder) throws {
        do {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        } catch {
            throw ConsultantError.from(error)
        }
    }
}
