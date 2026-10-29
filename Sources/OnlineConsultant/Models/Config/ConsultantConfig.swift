import Foundation

/// Runtime consultant configuration returned by `POST /connect`.
///
/// The backend uses this object to describe the consultant appearance, contact form,
/// consent settings, and auxiliary domain configuration.
package struct ConsultantConfig: Decodable, Equatable, Sendable {

    /// Chat title encoded as `name`.
    ///
    /// The SDK applies it to `OnlineConsultantViewController.title`.
    package let name: String?

    /// The consultant background theme encoded as `bg_color`.
    private let bgColor: BackgroundTheme?

    /// Indicates whether main consultant text and icons should use the inverse color scheme.
    package let inverse: Bool

    /// The consultant element shape encoded as `element_shape`.
    private let elementShape: ElementShape?

    /// The manager identity display mode encoded as `manager_display_type`.
    private let managerDisplayType: ManagerDisplayType?

    /// The custom manager display name encoded as `manager_name`.
    package let managerName: String?

    /// The custom manager avatar URL encoded as `manager_logo`.
    package let managerLogoURL: URL?

    /// The accent color encoded as `elements_color`.
    ///
    /// The backend returns the value as a hex string without a leading `#`.
    package let elementsColor: String?

    /// Indicates whether the unread counter is enabled.
    ///
    /// `nil` means the backend did not include `use_unread_counter`; `false` explicitly disables
    /// unread counting.
    package let useUnreadCounter: Bool?

    /// Welcome text encoded as `intro_text`.
    ///
    /// The SDK renders it as a local `_intro` text message only while the chat history is empty.
    package let introText: String?

    /// Indicates whether the offline mode is enabled for unavailable managers.
    package let useOfflineMode: Bool

    /// Text shown by the offline mode message encoded as `offline_text`.
    package let offlineText: String?

    /// Offline form field configuration encoded as `offline_form`.
    package let offlineForm: ConfigForm?

    /// Success text shown after offline form submission encoded as `offline_form_result_text`.
    package let offlineFormResultText: String?

    /// External consultant links encoded as `links`.
    package let links: [ConsultantLink]

    /// Web widget link display mode encoded as `links_mode`.
    package let linksMode: ConsultantLinksMode?

    /// Web widget links layout orientation encoded as `links_orientation`.
    package let linksOrientation: ConsultantLinksOrientation?

    /// Indicates whether web desktop widgets always show external links while the chat is closed.
    package let alwaysShowLinksOnDesktops: Bool

    /// Indicates whether personal data consent is required.
    package let personalDataConsent: Bool

    /// The privacy policy URL encoded as `personal_data_link`.
    package let personalDataLink: URL?

    /// Indicates whether the contact form is enabled for the consultant.
    package let useContactForm: Bool

    /// The contact form display strategy encoded as `contact_form_display`.
    package let contactFormDisplay: ContactFormDisplay?

    /// The contact form message text encoded as `contact_form_text`.
    package let contactFormText: String?

    /// The contact form field configuration encoded as `contact_form`.
    package let contactForm: ConfigForm?

    /// System domain configuration encoded as `domain_config`.
    package let domainConfig: DomainConfig?

    private enum CodingKeys: String, CodingKey {
        case name
        case bgColor = "bg_color"
        case inverse
        case elementShape = "element_shape"
        case managerDisplayType = "manager_display_type"
        case managerName = "manager_name"
        case managerLogo = "manager_logo"
        case elementsColor = "elements_color"
        case useUnreadCounter = "use_unread_counter"
        case introText = "intro_text"
        case useOfflineMode = "use_offline_mode"
        case offlineText = "offline_text"
        case offlineForm = "offline_form"
        case offlineFormResultText = "offline_form_result_text"
        case links
        case linksMode = "links_mode"
        case linksOrientation = "links_orientation"
        case alwaysShowLinksOnDesktops = "always_show_links_on_desktops"
        case personalDataConsent = "personal_data_consent"
        case personalDataLink = "personal_data_link"
        case useContactForm = "use_contact_form"
        case useContactFormCamel = "useContactForm"
        case contactFormDisplay = "contact_form_display"
        case contactFormDisplayCamel = "contactFormDisplay"
        case contactFormText = "contact_form_text"
        case contactFormTextCamel = "contactFormText"
        case contactForm = "contact_form"
        case contactFormCamel = "contactForm"
        case domainConfig = "domain_config"
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try Self.decodeTrimmedString(from: container, forKey: .name)
        bgColor = try Self.decodeEnum(from: container, forKey: .bgColor)
        inverse = try Self.decodeBool(from: container, forKey: .inverse)
        elementShape = try Self.decodeEnum(from: container, forKey: .elementShape)
        managerDisplayType = try Self.decodeEnum(from: container, forKey: .managerDisplayType)
        managerName = try Self.decodeTrimmedString(from: container, forKey: .managerName)
        managerLogoURL = try Self.decodeURL(from: container, forKey: .managerLogo)
        elementsColor = try Self.decodeTrimmedString(from: container, forKey: .elementsColor)
        useUnreadCounter = try Self.decodeBoolIfPresent(from: container, forKey: .useUnreadCounter)
        introText = try Self.decodeTrimmedString(from: container, forKey: .introText)
        useOfflineMode = try Self.decodeBool(from: container, forKey: .useOfflineMode)
        offlineText = try Self.decodeTrimmedString(from: container, forKey: .offlineText)
        offlineForm = try container.decodeIfPresent(ConfigForm.self, forKey: .offlineForm)
        offlineFormResultText = try Self.decodeTrimmedString(
            from: container,
            forKey: .offlineFormResultText
        )
        links = try container.decodeIfPresent([ConsultantLink].self, forKey: .links) ?? []
        linksMode = try Self.decodeTrimmedString(from: container, forKey: .linksMode)
            .map(ConsultantLinksMode.init(rawValue:))
        linksOrientation = try Self.decodeTrimmedString(from: container, forKey: .linksOrientation)
            .map(ConsultantLinksOrientation.init(rawValue:))
        alwaysShowLinksOnDesktops = try Self.decodeBool(from: container, forKey: .alwaysShowLinksOnDesktops)
        personalDataConsent = try Self.decodeBool(from: container, forKey: .personalDataConsent)
        personalDataLink = try Self.decodeURL(from: container, forKey: .personalDataLink)
        useContactForm = try Self.decodeBool(from: container, forKey: .useContactForm)
            || Self.decodeBoolIfPresent(from: container, forKey: .useContactFormCamel) == true
        contactFormDisplay = try Self.decodeEnum(from: container, forKey: .contactFormDisplay)
            ?? Self.decodeEnum(from: container, forKey: .contactFormDisplayCamel)
        contactFormText = try Self.decodeTrimmedString(from: container, forKey: .contactFormText)
            ?? Self.decodeTrimmedString(from: container, forKey: .contactFormTextCamel)
        contactForm = try container.decodeIfPresent(ConfigForm.self, forKey: .contactForm)
            ?? container.decodeIfPresent(ConfigForm.self, forKey: .contactFormCamel)
        domainConfig = try container.decodeIfPresent(DomainConfig.self, forKey: .domainConfig)
    }
}

package extension ConsultantConfig {

    /// External link settings exposed to host applications.
    var linkSettings: LinkSettings {
        LinkSettings(
            links: links,
            linksMode: linksMode,
            linksOrientation: linksOrientation,
            alwaysShowLinksOnDesktops: alwaysShowLinksOnDesktops
        )
    }

    /// Indicates whether the consultant uses the dark background theme.
    var isDarkBackground: Bool {
        bgColor == .dark
    }

    /// Indicates whether consultant elements should use rounded shapes.
    var roundedElements: Bool {
        elementShape != .rectangular
    }

    /// Indicates whether the consultant should use custom manager identity values.
    var usesCustomManagerDisplay: Bool {
        managerDisplayType == .custom
    }

    /// Non-empty image worker hosts from `domainConfig`.
    var imageWorkers: [String] {
        domainConfig?.imageWorkers.compactMap { worker in
            let trimmedWorker = worker.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedWorker.isEmpty ? nil : trimmedWorker
        } ?? []
    }
}

package extension ConsultantConfig {

    private static func decodeBool<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Bool {
        try decodeBoolIfPresent(from: container, forKey: key) ?? false
    }

    private static func decodeBoolIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Bool? {
        try container.decodeIfPresent(Bool.self, forKey: key)
    }

    private static func decodeTrimmedString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == true ? nil : value
    }

    private static func decodeEnum<Value: RawRepresentable, Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Value? where Value.RawValue == String {
        guard let value = try decodeTrimmedString(from: container, forKey: key) else {
            return nil
        }

        return Value(rawValue: value)
    }

    static func decodeURL<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> URL? {
        guard let value = try decodeTrimmedString(from: container, forKey: key) else {
            return nil
        }

        return URL(string: value)
    }
}
