import Core

public extension CrmSdk {

    /// Shared online consultant module configured during SDK initialization.
    var onlineConsultant: OnlineConsultantController {
        module(OnlineConsultantController.self) {
            let onlineConsultant = OnlineConsultantController(
                config: config.consultantConfig,
                sessionRuntime: sessionRuntime
            )
            Task {
                await sessionRuntime.addLifecycleListener(onlineConsultant)
            }
            return onlineConsultant
        }
    }
}
