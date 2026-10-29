import Foundation

/// Shared low-level runtime for SDK modules that use the client API.
package actor SessionRuntime {

    /// Semantic version of the connect module bundled with this package.
    nonisolated package static let version = "0.1.0"

    /// Runtime configuration used for connect requests.
    nonisolated package let config: SessionConfig
    nonisolated private let siteCustomerIdStore = SiteCustomerIdStore()

    nonisolated package var siteCustomerId: String? {
        siteCustomerIdStore.value
    }

    private let session: URLSession
    private let userTokenStorage: UserTokenStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) package var credentials: SessionCredentials?
    private(set) package var customerIdentity: CrmSdkCustomerIdentity?

    private var connectResponseData: Data?
    private var connectedResponse: ConnectResponse?
    private let initialPageContext: ConnectPageContext
    private let initialUser: ConnectUser
    private var connectTask: Task<Data, Error>?
    private var connectTaskID = UUID()
    private var lastConnectionError: CoreError?
    private var identityChangeTask: Task<Void, Error>?
    private var identityChangeGeneration = 0
    private var connectionGeneration = 0
    private var lifecycleListeners: [ObjectIdentifier: WeakSessionLifecycleListener] = [:]

    package init(
        config: SessionConfig,
        customerIdentity: CrmSdkCustomerIdentity? = nil,
        pageContext: ConnectPageContext = ConnectPageContext(),
        session: URLSession = NetworkSession.shared,
        userTokenStorage: UserTokenStorage? = nil
    ) {
        self.config = config
        self.customerIdentity = customerIdentity
        self.initialPageContext = pageContext
        self.initialUser = ConnectUser()
        self.session = session
        self.userTokenStorage = userTokenStorage ?? KeychainUserTokenStorage()
    }

    /// Opens or resumes a backend session through `POST /api/client/v1/connect`.
    @discardableResult
    package func start() async throws -> SessionCredentials {
        _ = try await connectionData()
        guard let credentials else {
            throw CoreError.missingConnectionCredentials
        }
        return credentials
    }

    /// Opens or resumes a backend session and decodes feature-specific bootstrap data.
    @discardableResult
    package func connect<Response>(
        responseType: Response.Type
    ) async throws -> Response where Response: Decodable {
        let data = try await connectionData()
        return try decoder.decode(Response.self, from: data)
    }

    /// Switches the shared customer identity and reconnects the common session.
    package func setCustomerIdentity(_ identity: CrmSdkCustomerIdentity?) async throws {
        let identity = try identity?.validated()
        try await enqueueIdentityChange {
            try await self.applyCustomerIdentity(identity)
        }
    }

    private func enqueueIdentityChange(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let previousTask = identityChangeTask
        identityChangeGeneration += 1
        let generation = identityChangeGeneration
        let task = Task {
            if let previousTask {
                _ = try? await previousTask.value
            }
            try await operation()
        }
        identityChangeTask = task

        defer {
            if generation == identityChangeGeneration {
                identityChangeTask = nil
            }
        }
        try await task.value
    }

    /// Registers a module only when the shared session is already connected. Does not connect or wait for connection.
    private func addConnectedLifecycleListener(
        _ listener: SessionLifecycleListener
    ) throws -> SessionCredentials {
        guard let credentials, connectedResponse != nil else {
            throw CoreError.missingConnectionCredentials
        }
        addLifecycleListener(listener)
        return credentials
    }

    /// Registers a module for shared session lifecycle changes.
    package func addLifecycleListener(_ listener: SessionLifecycleListener) {
        let key = ObjectIdentifier(listener)
        guard lifecycleListeners[key]?.value == nil else {
            return
        }

        lifecycleListeners = lifecycleListeners.filter { $0.value.value != nil }
        lifecycleListeners[key] = WeakSessionLifecycleListener(listener)
        if let credentials, let connectedResponse {
            listener.sessionDidConnect(
                credentials: credentials,
                pageContext: initialPageContext,
                user: initialUser,
                response: connectedResponse,
                customerIdentity: customerIdentity
            )
        } else if let lastConnectionError {
            listener.sessionDidFailToConnect(lastConnectionError)
        }
    }

    private func applyCustomerIdentity(_ identity: CrmSdkCustomerIdentity?) async throws {
        guard customerIdentity != identity else {
            _ = try await connectionData()
            return
        }

        disconnect()
        customerIdentity = identity
        _ = try await connectionData()
    }

    package func authorizedHeaders(contentType: Bool = true) throws -> [String: String] {
        guard let credentials else {
            throw CoreError.missingConnectionCredentials
        }
        var headers = siteHeaders(contentType: contentType)
        headers["X-User-Token"] = credentials.userToken
        headers["X-Session-Id"] = credentials.sessionID
        return headers
    }

    /// Returns credentials and customer identity from the same connected session.
    package func authorizedRequestContext() async throws -> (
        headers: [String: String], customerIdentity: CrmSdkCustomerIdentity?
    ) {
        _ = try await connectionData()
        return (try authorizedHeaders(), customerIdentity)
    }

    nonisolated package func siteHeaders(contentType: Bool = true) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Site-Token": config.siteToken
        ]
        if contentType {
            headers["Content-Type"] = "application/json"
        }
        if let customerSiteId = siteCustomerId {
            headers["X-Site-Customer-Id"] = customerSiteId
        }
        return headers
    }

    private func connectionData() async throws -> Data {
        if let connectResponseData {
            return connectResponseData
        }

        let generation = connectionGeneration
        let task: Task<Data, Error>
        let taskID: UUID

        if let connectTask {
            task = connectTask
            taskID = connectTaskID
        } else {
            taskID = UUID()
            connectTaskID = taskID
            lastConnectionError = nil
            let request: URLRequest
            do {
                customerIdentity = try customerIdentity?.validated()
                siteCustomerIdStore.set(customerIdentity?.siteCustomerId)
                request = try connectRequest()
            } catch {
                recordConnectionFailure(error)
                throw error
            }
            let session = self.session
            task = Task {
                let (data, response) = try await NetworkSession.data(
                    for: request, in: session
                )
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(statusCode) else {
                    throw CoreError.httpStatus(
                        statusCode,
                        CoreError.errorMessages(from: data)
                    )
                }
                return data
            }
            connectTask = task
        }

        do {
            let data = try await task.value
            guard generation == connectionGeneration, taskID == connectTaskID else {
                throw CancellationError()
            }

            if let connectResponseData {
                return connectResponseData
            }

            let response = try decoder.decode(ConnectResponse.self, from: data)
            try storeConnectResponse(response)
            connectResponseData = data
            connectTask = nil
            lastConnectionError = nil
            return data
        } catch {
            if generation == connectionGeneration, taskID == connectTaskID {
                connectTask = nil
                if !(error is CancellationError) { recordConnectionFailure(error) }
            }
            throw error
        }
    }

    private func recordConnectionFailure(_ error: Error) {
        let failure = CoreError.wrapping(error)
        guard lastConnectionError != failure else { return }
        lastConnectionError = failure
        lifecycleListeners.values.compactMap(\.value).forEach { $0.sessionDidFailToConnect(failure) }
    }

    private func connectRequest() throws -> URLRequest {
        let persistedToken = try userTokenStorage.getUserToken(
            siteToken: config.siteToken,
            customerIdentity: customerIdentity
        )
        let requestBody = ConnectRequest(
            user: initialUser.withToken(persistedToken),
            pageContext: initialPageContext
        )

        let url: URL = "connect"
            .split(separator: "/")
            .reduce(config.endpoints.clientAPIEndpointURL) { url, pathComponent in
                url.appendingPathComponent(String(pathComponent))
            }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        siteHeaders().forEach { header, value in
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.httpBody = try encoder.encode(requestBody)
        return request
    }

    private func storeConnectResponse(_ response: ConnectResponse) throws {
        guard let credentials = response.credentials else {
            throw CoreError.missingConnectionCredentials
        }

        try userTokenStorage.setUserToken(
            credentials.userToken,
            siteToken: config.siteToken,
            customerIdentity: customerIdentity
        )
        self.credentials = credentials
        connectedResponse = response
        lastConnectionError = nil
        lifecycleListeners.values.compactMap(\.value).forEach {
            $0.sessionDidConnect(
                credentials: credentials,
                pageContext: initialPageContext,
                user: initialUser,
                response: response,
                customerIdentity: customerIdentity
            )
        }
    }

    private func disconnect() {
        connectionGeneration += 1
        connectTask?.cancel()
        connectTask = nil
        connectTaskID = UUID()
        lastConnectionError = nil
        connectResponseData = nil
        connectedResponse = nil
        credentials = nil
        siteCustomerIdStore.set(nil)
        lifecycleListeners.values.compactMap(\.value).forEach {
            $0.sessionDidDisconnect()
        }
    }
}

private final class WeakSessionLifecycleListener {
    weak var value: (any SessionLifecycleListener)?
    init(_ value: any SessionLifecycleListener) { self.value = value }
}

private final class SiteCustomerIdStore: @unchecked Sendable {
    private let lock = NSLock()
    private var siteCustomerId: String?

    var value: String? {
        lock.withLock { siteCustomerId }
    }

    func set(_ id: String?) {
        lock.withLock { siteCustomerId = id }
    }
}
