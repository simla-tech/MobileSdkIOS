import Foundation

/// Backend key of a contact form field.
///
/// The backend has known field keys such as `name`, `phone`, `email`, `personalData`,
/// and `marketingConsent`, but site actions may also contain custom field keys. Unknown keys are
/// preserved as `.custom` so the SDK can render them instead of dropping backend configuration.
package enum ContactFormFieldKey: Hashable, Codable, Sendable, ExpressibleByStringLiteral {

    /// Customer name field.
    case name

    /// Customer phone field.
    case phone

    /// Customer email field.
    case email

    /// Required personal-data consent field.
    case personalData

    /// Optional or required marketing consent field.
    case marketingConsent

    /// Custom backend field key not known by the SDK.
    case custom(String)

    /// Backend string value for this field key.
    package var rawValue: String {
        switch self {
        case .name:
            return "name"
        case .phone:
            return "phone"
        case .email:
            return "email"
        case .personalData:
            return "personalData"
        case .marketingConsent:
            return "marketingConsent"
        case .custom(let value):
            return value
        }
    }

    /// Creates a field key from a backend string value.
    package init(_ rawValue: String) {
        switch rawValue {
        case "name":
            self = .name
        case "phone":
            self = .phone
        case "email":
            self = .email
        case "personalData":
            self = .personalData
        case "marketingConsent":
            self = .marketingConsent
        default:
            self = .custom(rawValue)
        }
    }

    package init(stringLiteral value: String) {
        self.init(value)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ContactFormFieldKey: Comparable {

    package static func < (
        lhs: ContactFormFieldKey,
        rhs: ContactFormFieldKey
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

package extension Dictionary where Key == ContactFormFieldKey {

    /// Accesses field dictionaries by a backend string key.
    subscript(_ rawKey: String) -> Value? {
        get {
            self[ContactFormFieldKey(rawKey)]
        }
        set {
            self[ContactFormFieldKey(rawKey)] = newValue
        }
    }
}

package extension Dictionary where Key == ContactFormFieldKey {

    init(backendFields: [String: Value]) {
        self.init(
            uniqueKeysWithValues: backendFields.map {
                (ContactFormFieldKey($0.key), $0.value)
            }
        )
    }

    var backendFields: [String: Value] {
        Swift.Dictionary<String, Value>(
            uniqueKeysWithValues: map {
                ($0.key.rawValue, $0.value)
            }
        )
    }
}
