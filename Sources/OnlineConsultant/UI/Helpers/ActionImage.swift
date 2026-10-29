import CoreGraphics
import Foundation

/// Preinstalled action image shown in contact-form messages.
package enum ActionImage {

    /// Greeting illustration bundled with the SDK.
    case hello

    /// Gift illustration bundled with the SDK.
    case present

    /// Fire illustration bundled with the SDK.
    case fire

    /// Confetti illustration bundled with the SDK.
    case confetti

    /// Creates a bundled action image from the backend preinstalled image identifier.
    package init?(preinstalledID value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        switch value {
        case "1":
            self = .hello
        case "2":
            self = .present
        case "3":
            self = .fire
        case "4":
            self = .confetti
        default:
            return nil
        }
    }

    /// Backend identifier for this bundled action image.
    package var preinstalledID: String {
        switch self {
        case .hello:
            return "1"
        case .present:
            return "2"
        case .fire:
            return "3"
        case .confetti:
            return "4"
        }
    }

    /// URL of the bundled PNG resource for this action image.
    package var preinstalledURL: URL? {
        imageResource.fileURL
    }

    /// Intrinsic bitmap size used by the frontend for this bundled action image.
    package var preinstalledSize: CGSize {
        switch self {
        case .hello, .present, .fire:
            return CGSize(width: 323, height: 256)
        case .confetti:
            return CGSize(width: 324, height: 256)
        }
    }

    /// Returns a valid remote, data, or file URL from backend/custom image value.
    package static func remoteURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let normalizedValue = value.hasPrefix("//") ? "https:\(value)" : value

        guard
            let url = URL(string: normalizedValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https", "data", "file"].contains(scheme)
        else {
            return nil
        }

        return url
    }

    /// Image resource for this bundled action image.
    private var imageResource: ConsultantImageResource {
        switch self {
        case .hello:
            return .actionHello
        case .present:
            return .actionPresent
        case .fire:
            return .actionFire
        case .confetti:
            return .actionConfetti
        }
    }
}
