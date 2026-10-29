/// User consent state for tracker events.
public enum TrackerConsentState: Equatable, Sendable {

    /// Consent has not been explicitly granted or denied.
    case unknown

    /// User granted permission to send tracker events.
    case granted

    /// User denied permission to send tracker events.
    case denied
}
