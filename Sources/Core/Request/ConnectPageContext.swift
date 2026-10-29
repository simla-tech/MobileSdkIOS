import Foundation

/// Page or screen metadata sent while initializing a backend session.
public struct ConnectPageContext: Codable, Equatable, Sendable {

    /// Current page or screen title encoded as `page_title`.
    public let title: String?

    /// URL used for tracker event filtering on the backend.
    public let url: URL?

    /// Current URL encoded as `refer_url` for backend session metadata.
    public let referURL: URL?

    /// Creates page or screen metadata for the connect request.
    ///
    /// - Parameters:
    ///   - title: Optional title of the current screen or page.
    ///   - url: Optional page URL used for backend tracker filtering.
    ///   - referURL: Optional URL sent as `refer_url` in the connect request.
    public init(
        title: String? = nil,
        url: URL? = nil,
        referURL: URL? = nil
    ) {
        self.title = title
        self.url = url
        self.referURL = referURL
    }
}

extension ConnectPageContext {
    private struct CodingValue: Codable {
        let title: String?
        let url: URL?
        let referURL: URL?
    }

    /// Decodes a `ConnectPageContext` value from its serialized representation.
    ///
    /// - Parameters:
    ///   - decoder: Decoder containing the encoded value.
    public init(from decoder: Decoder) throws {
        do {
            let value = try CodingValue(from: decoder)
            self.init(title: value.title, url: value.url, referURL: value.referURL)
        } catch {
            throw CoreError.wrapping(error)
        }
    }

    /// Encodes this `ConnectPageContext` value for serialization.
    ///
    /// - Parameters:
    ///   - encoder: Encoder receiving this value.
    public func encode(to encoder: Encoder) throws {
        do {
            try CodingValue(title: title, url: url, referURL: referURL).encode(to: encoder)
        } catch {
            throw CoreError.wrapping(error)
        }
    }
}
