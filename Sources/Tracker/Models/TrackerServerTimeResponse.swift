import Foundation

package struct TrackerServerTimeResponse: Decodable, Equatable, Sendable {
    package let timestamp: String?

    private enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
    }

    package init(timestamp: String?) {
        self.timestamp = timestamp
    }
}
