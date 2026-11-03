import Core

public extension CrmSdk {

    /// Shared push module that registers application-supplied tokens and handles notification events.
    var pushService: PushService {
        sharedPushService(for: .direct)
    }
}

private extension CrmSdk {

    func sharedPushService(for kind: ConsultantPushModuleKind) -> PushService {
        claimPushModule(kind)
        return module(PushService.self) {
            let pushService = PushService(
                sessionRuntime: sessionRuntime,
                pushHandler: .init(
                    siteToken: sessionRuntime.config.siteToken,
                    clientAPIEndpointURL: sessionRuntime.config.endpoints.clientAPIEndpointURL
                )
            )

            Task {
                await sessionRuntime.addLifecycleListener(pushService)
            }

            return pushService
        }
    }
}

