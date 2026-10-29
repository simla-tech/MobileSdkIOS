import UIKit

/// Centralized image resources used by the SDK UI.
package enum ConsultantImageResource {

    case actionHello
    case actionPresent
    case actionFire
    case actionConfetti

    case attachmentIcon
    case botIcon
    case contactAvatar
    case infoIcon
    case sendIcon
    case close

    case arrowClockwise
    case checkboxOff
    case checkboxOn
    case clock
    case document
    case errorCircle
    case errorTriangle
    case paperclip
    case person
    case photo


    /// Loads the UIKit image for this bundled asset or SF Symbol.
    package var image: UIImage? {
        switch self {
        case .actionHello, .actionPresent, .actionFire, .actionConfetti:
            return fileURL.flatMap { UIImage(contentsOfFile: $0.path) }
        case .attachmentIcon:
            return bundledImage(named: "consultant_attachment_icon")
        case .botIcon:
            return bundledImage(named: "consultant_bot_icon")
        case .contactAvatar:
            return bundledImage(named: "consultant_contact_avatar")
        case .infoIcon:
            return bundledImage(named: "consultant_info_icon")
        case .sendIcon:
            return bundledImage(named: "consultant_send_icon")
        case .close:
            return bundledImage(named: "consultant_close_icon")
        case .arrowClockwise:
            return systemImage(named: "arrow.clockwise")
        case .checkboxOff:
            return systemImage(named: "square")
        case .checkboxOn:
            return systemImage(named: "checkmark.square.fill")
        case .clock:
            return systemImage(named: "clock")
        case .document:
            return systemImage(named: "doc.fill")
        case .errorCircle:
            return systemImage(named: "exclamationmark.circle")
        case .errorTriangle:
            return systemImage(named: "exclamationmark.triangle.fill")
        case .paperclip:
            return systemImage(named: "paperclip")
        case .person:
            return systemImage(named: "person.fill")
        case .photo:
            return systemImage(named: "photo")
        }
    }

    /// Loads the image with template rendering mode for tint-driven icons.
    package var templateImage: UIImage? {
        image?.withRenderingMode(.alwaysTemplate)
    }

    /// URL for bundled file resources that are loaded by path instead of asset name.
    package var fileURL: URL? {
        switch self {
        case .actionHello:
            return bundledFileURL(named: "hello", fileExtension: "png", subdirectory: "ActionImages")
        case .actionPresent:
            return bundledFileURL(named: "present", fileExtension: "png", subdirectory: "ActionImages")
        case .actionFire:
            return bundledFileURL(named: "fire", fileExtension: "png", subdirectory: "ActionImages")
        case .actionConfetti:
            return bundledFileURL(named: "confetti", fileExtension: "png", subdirectory: "ActionImages")
        case .attachmentIcon,
             .botIcon,
             .contactAvatar,
             .infoIcon,
             .sendIcon,
             .close,
             .arrowClockwise,
             .checkboxOff,
             .checkboxOn,
             .clock,
             .document,
             .errorCircle,
             .errorTriangle,
             .paperclip,
             .person,
             .photo:
            return nil
        }
    }

    private func bundledImage(named name: String) -> UIImage? {
        UIImage(
            named: name,
            in: .module,
            compatibleWith: nil
        )
    }

    private func systemImage(named name: String) -> UIImage? {
        UIImage(systemName: name)
    }

    private func bundledFileURL(
        named name: String,
        fileExtension: String,
        subdirectory: String
    ) -> URL? {
        Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.module.url(
            forResource: name,
            withExtension: fileExtension
        )
    }
}
