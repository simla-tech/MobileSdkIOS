import Foundation

/// Optional manager identity override resolved from consultant configuration for UI rendering.
package struct ManagerIdentity: Equatable {

    /// Custom manager name displayed instead of the message user name.
    package let displayName: String?

    /// Custom manager avatar URL displayed instead of the message user avatar.
    package let logoURL: URL?

    /// Builds the manager identity only when custom manager display is enabled in consultant config.
    package init(config: ConsultantConfig?) {
        guard config?.usesCustomManagerDisplay == true else {
            displayName = nil
            logoURL = nil
            return
        }

        displayName = config?.managerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        logoURL = config?.managerLogoURL
    }
}
