import Core
import Foundation

/// Thread-safe storage for mutable tracker settings.
package final class TrackerStateStore: @unchecked Sendable {

    private let lock = NSLock()
    private var state = TrackerState()

    package var currentState: TrackerState {
        lock.withLock {
            state
        }
    }

    package init() {}

    @discardableResult
    package func setSystemCustomerID(_ id: Int64?) -> Int64? {
        lock.withLock {
            guard let id else {
                state.systemCustomerID = nil
                return nil
            }

            guard id > 0 else {
                return state.systemCustomerID
            }

            state.systemCustomerID = id
            return id
        }
    }

    @discardableResult
    package func setSiteCustomerID(_ id: String?) -> String? {
        lock.withLock {
            state.siteCustomerID = id?.nilIfEmpty
            return state.siteCustomerID
        }
    }

    package func setAvailability(_ isAvailable: Bool, requiresConsent: Bool) {
        lock.withLock {
            state.isAvailable = isAvailable
            state.requiresConsent = requiresConsent
        }
    }

    package func setConsent(_ consent: TrackerConsentState) {
        lock.withLock {
            state.consentState = consent
        }
    }
}
