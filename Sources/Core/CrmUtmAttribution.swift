import Foundation

package struct CrmUtmAttribution: Codable, Equatable, Sendable {
    package let source: String?
    package let medium: String?
    package let campaign: String?
    package let term: String?
    package let content: String?

    package init?(source: String? = nil, medium: String? = nil, campaign: String? = nil,
                  term: String? = nil, content: String? = nil) {
        func normalized(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        self.source = normalized(source)
        self.medium = normalized(medium)
        self.campaign = normalized(campaign)
        self.term = normalized(term)
        self.content = normalized(content)
        guard [self.source, self.medium, self.campaign, self.term, self.content].contains(where: { $0 != nil }) else { return nil }
    }

    private enum CodingKeys: String, CodingKey {
        case source = "utm_source"
        case medium = "utm_medium"
        case campaign = "utm_campaign"
        case term = "utm_keyword"
        case content = "utm_content"
    }
}

package final class CrmUtmAttributionStorage: @unchecked Sendable {
    package static let shared = CrmUtmAttributionStorage()
    private let lock = NSLock()
    private var attribution: CrmUtmAttribution?

    package func save(_ attribution: CrmUtmAttribution) {
        lock.withLock { self.attribution = attribution }
    }

    package func load() -> CrmUtmAttribution? {
        lock.withLock { attribution }
    }

    package func clear() {
        lock.withLock { attribution = nil }
    }

    private init() {}
}
