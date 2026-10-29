import Foundation

/// Push identifier received from Firebase.
public enum PushToken: Equatable, Sendable {
    /// Firebase installation ID.
    case fid(String)

    /// Firebase Cloud Messaging registration token.
    case fcm(String)

    package var fidValue: String? {
        if case .fid(let value) = self {
            return value
        }
        return nil
    }

    package var fcmValue: String? {
        if case .fcm(let value) = self {
            return value
        }
        return nil
    }
}

package extension PushToken {

    func normalizedToken() throws -> PushToken {
        switch self {
        case let .fid(value):
            guard let value = value.nilIfEmpty else {
                throw PushServiceError.emptyFID
            }
            return .fid(value)
        case let .fcm(value):
            guard let value = value.nilIfEmpty else {
                throw PushServiceError.emptyFCMToken
            }
            return .fcm(value)
        }
    }

}
