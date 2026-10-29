import Foundation

/// External consultant link returned in `config.links`.
///
/// The backend uses these links for social networks and messenger channels. The SDK exposes the
/// decoded data to host applications and does not render these links in its built-in UI.
public struct ConsultantLink: Codable, Equatable, Sendable {

    /// Link type encoded as `type`, for example `telegram`, `whatsapp`, or `vk`.
    public let type: ConsultantLinkType?

    /// Backend link value encoded as `url`.
    ///
    /// Depending on `type`, this can be a full URL, username, channel id, or phone number.
    public let url: String?

    /// Optional backend prefix encoded as `prefix`.
    ///
    /// Telegram links can use prefixes such as `t.me/` or `teleg.run/`.
    public let prefix: String?

    /// Creates an external consultant link value.
    ///
    /// - Parameters:
    ///   - type: Type of external consultant link.
    ///   - url: Backend link value, which may be a URL, username, channel ID, or phone number.
    ///   - prefix: Optional prefix used to form the consultant link URL.
    public init(
        type: ConsultantLinkType? = nil,
        url: String? = nil,
        prefix: String? = nil
    ) {
        self.type = type
        self.url = url
        self.prefix = prefix
    }

    /// Best-effort URL built with the same known type prefixes as the web widget.
    public var resolvedURL: URL? {
        guard let value = url?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let directURL = URL(string: value), directURL.scheme != nil {
            return directURL
        }

        if let prefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty {
            return URL(string: "https://\(prefix)\(value)")
        }

        guard let type else {
            return URL(string: value)
        }

        return URL(string: type.commonURLPrefix + value)
    }
}

extension ConsultantLink {
    private struct CodingValue: Codable {
        let type: ConsultantLinkType?
        let url: String?
        let prefix: String?
    }

    /// Decodes a `ConsultantLink` from its serialized representation.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        do {
            let value = try CodingValue(from: decoder)
            self.init(type: value.type, url: value.url, prefix: value.prefix)
        } catch {
            throw ConsultantError.from(error)
        }
    }

    /// Encodes this `ConsultantLink` for serialization.
    ///
    /// - Parameters:
    ///   - encoder: Encoder receiving this value.
    public func encode(to encoder: Encoder) throws {
        do {
            try CodingValue(type: type, url: url, prefix: prefix).encode(to: encoder)
        } catch {
            throw ConsultantError.from(error)
        }
    }
}

/// Known external consultant link types returned in `config.links[].type`.
public enum ConsultantLinkType: Codable, Equatable, Sendable, ExpressibleByStringLiteral {

    /// Facebook profile/page link.
    case fb

    /// Facebook Messenger link.
    case fbmessenger

    /// WhatsApp link.
    case whatsapp

    /// Telegram link.
    case telegram

    /// VK link.
    case vk

    /// Viber public account link.
    case viber

    /// Instagram link.
    case instagram

    /// MAX messenger link.
    case max

    /// Link type that is not known by this SDK version.
    case unknown(String)

    /// String value used in backend JSON payloads.
    public var rawValue: String {
        switch self {
        case .fb:
            return "fb"
        case .fbmessenger:
            return "fbmessenger"
        case .whatsapp:
            return "whatsapp"
        case .telegram:
            return "telegram"
        case .vk:
            return "vk"
        case .viber:
            return "viber"
        case .instagram:
            return "instagram"
        case .max:
            return "max"
        case .unknown(let value):
            return value
        }
    }

    package var commonURLPrefix: String {
        switch self {
        case .fb:
            return "https://fb.me/"
        case .fbmessenger:
            return "https://m.me/"
        case .whatsapp:
            return "https://wa.me/"
        case .telegram:
            return "https://t.me/"
        case .vk:
            return "https://vk.me/"
        case .viber:
            return "viber://pa?chatURI="
        case .instagram:
            return "https://instagram.com/"
        case .max, .unknown:
            return ""
        }
    }

    /// Creates a link type from a backend string value.
    ///
    /// - Parameters:
    ///   - rawValue: Value received from the consultant backend.
    public init(rawValue: String) {
        switch rawValue {
        case "fb":
            self = .fb
        case "fbmessenger":
            self = .fbmessenger
        case "whatsapp":
            self = .whatsapp
        case "telegram":
            self = .telegram
        case "vk":
            self = .vk
        case "viber":
            self = .viber
        case "instagram":
            self = .instagram
        case "max":
            self = .max
        default:
            self = .unknown(rawValue)
        }
    }

    /// Creates a consultant link type from a string literal.
    ///
    /// - Parameters:
    ///   - value: String literal representing a backend value.
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    /// Decodes a `ConsultantLinkType` value from its serialized representation.
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

    /// Encodes this `ConsultantLinkType` value for serialization.
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
