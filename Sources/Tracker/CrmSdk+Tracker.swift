import Core

public extension CrmSdk {

    /// Shared tracker module configured during SDK initialization.
    var tracker: Tracker {
        module(Tracker.self) {
            Tracker(
                config: config.trackerConfig,
                sessionRuntime: sessionRuntime
            )
        }
    }
}
