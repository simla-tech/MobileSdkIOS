import Core
import Tracker

public extension CrmSdk {

    /// Shared recommendations module configured during SDK initialization.
    var recommendations: Recommendations {
        module(Recommendations.self) {
            let tracker = self.tracker
            return Recommendations(
                sessionRuntime: sessionRuntime,
                tracker: tracker
            )
        }
    }
}
