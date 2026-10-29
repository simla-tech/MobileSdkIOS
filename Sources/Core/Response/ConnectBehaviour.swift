/// Runtime availability flags returned by `POST /connect`.
package struct ConnectBehaviour: Decodable, Equatable, Sendable {

    /// Indicates whether consultant managers are currently considered offline.
    package let isOffline: Bool

    /// Indicates whether the chat widget part is available for the current site.
    package let widget: Bool?

    /// Indicates whether tracker events are accepted for the current site.
    package let tracker: Bool?

    /// Indicates whether Global Privacy Control is enabled for the current request.
    private let gpc: Bool?

    /// Indicates whether tracker events require explicit consent.
    package let consentForm: Bool?

    package init(
        isOffline: Bool = false,
        widget: Bool? = nil,
        tracker: Bool? = nil,
        gpc: Bool? = nil,
        consentForm: Bool? = nil
    ) {
        self.isOffline = isOffline
        self.widget = widget
        self.tracker = tracker
        self.gpc = gpc
        self.consentForm = consentForm
    }

    private enum CodingKeys: String, CodingKey {
        case isOffline = "is_offline"
        case widget
        case tracker
        case gpc
        case consentForm = "consent_form"
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isOffline = try container.decodeIfPresent(Bool.self, forKey: .isOffline) ?? false
        self.widget = try container.decodeIfPresent(Bool.self, forKey: .widget)
        self.tracker = try container.decodeIfPresent(Bool.self, forKey: .tracker)
        self.gpc = try container.decodeIfPresent(Bool.self, forKey: .gpc)
        self.consentForm = try container.decodeIfPresent(Bool.self, forKey: .consentForm)
    }
}
