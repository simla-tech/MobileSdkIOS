import Foundation

//
//  DomainConfig.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 17.07.2026.
//

/// System domain configuration returned in `config.domain_config`.
package struct DomainConfig: Decodable, Equatable, Sendable {

    /// Branding URL opened when the footer logo is tapped.
    package let url: URL?

    /// Branding logo URL displayed in the footer.
    package let logo: URL?

    /// Indicates whether the connected CRM is on a free plan.
    private let free: Bool

    /// Indicates whether the SDK should show the branding footer.
    package let footer: Bool

    /// Image worker hosts used to transform image URLs.
    package let imageWorkers: [String]

    private enum CodingKeys: String, CodingKey {
        case url = "URL"
        case logo
        case free
        case footer
        case imageWorkers = "image_workers"
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try Self.decodeURL(from: container, forKey: .url)
        logo = try Self.decodeURL(from: container, forKey: .logo)
        free = try container.decodeIfPresent(Bool.self, forKey: .free) ?? false
        footer = try container.decodeIfPresent(Bool.self, forKey: .footer) ?? false
        imageWorkers = try container.decodeIfPresent([String].self, forKey: .imageWorkers) ?? []
    }

    private static func decodeURL<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> URL? {
        guard
            let value = try container.decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }

        return URL(string: value)
    }
}
