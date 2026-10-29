import Foundation

/// Process-wide Consultant SDK instance.
@MainActor
public final class CrmSdk {
    private static var instance: CrmSdk?

    /// Returns the initialized SDK instance.
    public static var shared: CrmSdk {
        guard let instance else {
            preconditionFailure("Call Consultant.initialize(config:) before using Consultant.shared.")
        }
        return instance
    }

    package let config: CrmSdkConfig
    package let sessionRuntime: SessionRuntime

    private var modules: [ObjectIdentifier: AnyObject] = [:]
    private var pushModuleKind: ConsultantPushModuleKind?

    /// Creates the process-wide SDK instance and waits for its shared connection.
    /// Start modules after this method returns successfully.
    ///
    /// - Parameters:
    ///   - config: Shared SDK settings.
    ///   - customerIdentity: Optional retailCRM customer identity for the shared session.
    ///   - pageContext: Page or screen metadata for the initial connection.
    @discardableResult
    public static func initialize(
        config: CrmSdkConfig,
        customerIdentity: CrmSdkCustomerIdentity? = nil,
        pageContext: ConnectPageContext = ConnectPageContext()
    ) async throws -> CrmSdk {
        let sdk = createInstance(
            config: config,
            customerIdentity: customerIdentity,
            pageContext: pageContext
        )
        try await sdk.startConnection()
        return sdk
    }

    private static func createInstance(
        config: CrmSdkConfig,
        customerIdentity: CrmSdkCustomerIdentity?,
        pageContext: ConnectPageContext
    ) -> CrmSdk {
        precondition(instance == nil, "Consultant SDK is already initialized.")

        NetworkSession.configure(
            requestTimeout: config.requestTimeout,
            resourceTimeout: config.resourceTimeout,
            observer: config.networkObserver
        )

        let consultant = CrmSdk(
            config: config,
            customerIdentity: customerIdentity,
            pageContext: pageContext
        )
        instance = consultant
        return consultant
    }

    private init(
        config: CrmSdkConfig,
        customerIdentity: CrmSdkCustomerIdentity?,
        pageContext: ConnectPageContext
    ) {
        self.config = config
        self.sessionRuntime = SessionRuntime(
            config: SessionConfig(siteToken: config.siteToken, baseURL: config.baseURL),
            customerIdentity: customerIdentity,
            pageContext: pageContext
        )
    }

    /// Switches the shared customer identity and reconnects the SDK.
    ///
    /// - Parameters:
    ///   - identity: New retailCRM customer identity; pass `nil` for an anonymous session.
    public func setCustomerIdentity(_ identity: CrmSdkCustomerIdentity?) async throws {
        do {
            try await sessionRuntime.setCustomerIdentity(identity)
        } catch {
            throw CoreError.wrapping(error)
        }
    }

    /// Returns the existing module instance or creates it on first access.
    package func module<Module: AnyObject>(
        _ type: Module.Type,
        create: () -> Module
    ) -> Module {
        let key = ObjectIdentifier(type)
        if let module = modules[key] as? Module {
            return module
        }

        let module = create()
        modules[key] = module
        return module
    }

    package func claimPushModule(_ kind: ConsultantPushModuleKind) {
        guard let pushModuleKind else {
            pushModuleKind = kind
            return
        }
        precondition(
            pushModuleKind == kind,
            "PushService cannot be installed simultaneously."
        )
    }

    private func startConnection() async throws {
        do {
            _ = try await sessionRuntime.start()
        } catch {
            throw CoreError.wrapping(error)
        }
    }
}

/// Completion-based Core API.
public extension CrmSdk {

    /// Creates the process-wide SDK instance and starts its shared connection in the background.
    /// Start modules after receiving success in the completion, which runs on the main actor.
    /// The SDK instance is returned before the connection finishes.
    ///
    /// - Parameters:
    ///   - config: Shared SDK settings.
    ///   - customerIdentity: Optional retailCRM customer identity for the shared session.
    ///   - pageContext: Page or screen metadata for the initial connection.
    ///   - completion: Called on the main actor with the initial connection result.
    @discardableResult
    static func initialize(
        config: CrmSdkConfig,
        customerIdentity: CrmSdkCustomerIdentity? = nil,
        pageContext: ConnectPageContext = ConnectPageContext(),
        completion: @escaping (Result<Void, CoreError>) -> Void
    ) -> CrmSdk {
        let sdk = createInstance(
            config: config,
            customerIdentity: customerIdentity,
            pageContext: pageContext
        )
        Task {
            do {
                try await sdk.startConnection()
                completion(.success(()))
            } catch {
                completion(.failure(CoreError.wrapping(error)))
            }
        }
        return sdk
    }

    /// Switches the shared customer identity and reports the reconnection result.
    /// The completion runs on the main actor.
    func setCustomerIdentity(
        _ identity: CrmSdkCustomerIdentity?,
        completion: @escaping (Result<Void, CoreError>) -> Void = { _ in }
    ) {
        Task {
            do {
                try await setCustomerIdentity(identity)
                completion(.success(()))
            } catch {
                completion(.failure(CoreError.wrapping(error)))
            }
        }
    }
}

package enum ConsultantPushModuleKind {
    case direct
    case firebase
}
