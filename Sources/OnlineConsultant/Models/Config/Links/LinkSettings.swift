/// External consultant link configuration received from the backend.
public struct LinkSettings: Equatable, Sendable {

    /// External consultant links from `config.links`.
    public let links: [ConsultantLink]

    /// Link display mode from `config.links_mode`.
    public let linksMode: ConsultantLinksMode?

    /// Link layout orientation from `config.links_orientation`.
    public let linksOrientation: ConsultantLinksOrientation?

    /// Whether web desktop widgets always show links while the chat is closed.
    public let alwaysShowLinksOnDesktops: Bool

    /// Creates external consultant link settings.
    public init(
        links: [ConsultantLink] = [],
        linksMode: ConsultantLinksMode? = nil,
        linksOrientation: ConsultantLinksOrientation? = nil,
        alwaysShowLinksOnDesktops: Bool = false
    ) {
        self.links = links
        self.linksMode = linksMode
        self.linksOrientation = linksOrientation
        self.alwaysShowLinksOnDesktops = alwaysShowLinksOnDesktops
    }
}
