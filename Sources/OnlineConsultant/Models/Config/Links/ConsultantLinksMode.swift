/// Known display modes returned in `config.links_mode`.
public enum ConsultantLinksMode: Codable, Equatable, Sendable, ExpressibleByStringLiteral {

    /// Standard consultant link style.
    case standard

    /// Black consultant link style.
    case black

    /// Grey consultant link style.
    case grey

    /// Widget-colored link style.
    case widget

    /// Links mode that is not known by this SDK version.
    case unknown(String)

    /// String value used in backend JSON payloads.
    public var rawValue: String {
        switch self {
        case .standard:
            return "standard"
        case .black:
            return "black"
        case .grey:
            return "grey"
        case .widget:
            return "widget"
        case .unknown(let value):
            return value
        }
    }

    /// Creates a links mode from a backend string value.
    ///
    /// - Parameters:
    ///   - rawValue: Value received from the consultant backend.
    public init(rawValue: String) {
        switch rawValue {
        case "standard":
            self = .standard
        case "black":
            self = .black
        case "grey":
            self = .grey
        case "widget":
            self = .widget
        default:
            self = .unknown(rawValue)
        }
    }

    /// Creates a consultant links display mode from a string literal.
    ///
    /// - Parameters:
    ///   - value: String literal representing a backend value.
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    /// Decodes a `ConsultantLinksMode` value from its serialized representation.
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

    /// Encodes this `ConsultantLinksMode` value for serialization.
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
