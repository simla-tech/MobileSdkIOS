import Core
import Foundation

/// Main controller facade for the online consultant session.
///
/// Tracks the shared chat session, its connection state, unread messages, configuration, and file cache.
@MainActor
public final class OnlineConsultantController {

    /// Current connection state; observe changes through `onStateChange`.
    public private(set) var state: ControllerState = .idle
    /// Calls the handler with the current state when assigned, then whenever it changes.
    public var onStateChange: ((ControllerState) -> Void)? {
        didSet { onStateChange?(state) }
    }
    /// Latest connect response received from the backend.
    package private(set) var connectResponse: ConsultantConnectResponse?
    /// Messages currently known by the controller.
    package var messages: [ConsultantMessage] {
        messageStore.messagesWithResolvedQuotes
    }
    /// consultant configuration received from the backend.
    package private(set) var consultantConfig: ConsultantConfig?
    /// Indicates whether the consultant is currently offline.
    package private(set) var isOffline = false
    /// Number of unread incoming messages in the loaded history; zero when the counter is disabled.
    /// Observe changes through `onUnreadIncomingMessagesCountChange`.
    public private(set) var unreadIncomingMessagesCount = 0
    /// Calls the handler with the current unread count when assigned, then whenever it changes.
    public var onUnreadIncomingMessagesCountChange: ((Int) -> Void)? {
        didSet { onUnreadIncomingMessagesCountChange?(unreadIncomingMessagesCount) }
    }
    /// Indicates whether older messages can be requested.
    package private(set) var canLoadOlderMessages = false
    /// Current contact-form presentation state.
    package private(set) var contactFormPresentation: ContactFormPresentation = .hidden
    /// Attachments prepared in the message input but not sent yet.
    package var inputAttachments: [InputAttachment] {
        inputAttachmentStore.attachments
    }

    /// Indicates whether all prepared input attachments are ready to be sent.
    package var canSendInputAttachments: Bool {
        inputAttachmentStore.canSend
    }

    private let client: OnlineConsultantClient
    private var startTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private let applicationLifecycle: ConsultantApplicationLifecycle
    private var realtimeSessionGeneration: UUID?
    private var realtimeGeneration = UUID()
    private var brandingLogoLoadTask: ImageLoadTask?
    private var connectionGeneration = UUID()
    private var isAnonymousSession = true
    private let contactFormActionCoordinator: ContactFormActionCoordinator
    private let messageReadCoordinator: MessageReadCoordinator
    private let messageSender: MessageSender
    private var contactFormState = ContactFormState()
    private var inputAttachmentStore = InputAttachmentStore()
    private var messageStore = MessageStore()
    private let fileCache: ConsultantFileCache
    private let cachePolicy: OnlineConsultantCachePolicy
    private let remoteFileCacheLoader: ConsultantRemoteFileCacheLoading
    private let messageFileLinkCoordinator: MessageFileLinkCoordinator
    package private(set) var internalState: ControllerInternalState = .idle
    private let eventBroadcaster = AsyncBroadcaster<ControllerEvent>()
    private let stateBroadcaster = AsyncBroadcaster<ControllerState>()
    private let internalStateBroadcaster = AsyncBroadcaster<ControllerInternalState>()
    private let messageBroadcaster = AsyncBroadcaster<[ConsultantMessage]>()
    private let inputAttachmentBroadcaster = AsyncBroadcaster<[InputAttachment]>()

    package convenience init(
        config: OnlineConsultantConfig,
        sessionRuntime: SessionRuntime
    ) {
        self.init(
            client: OnlineConsultantClient(
                config: config,
                sessionRuntime: sessionRuntime
            ),
            cachePolicy: config.cachePolicy
        )
    }

    package init(
        client: OnlineConsultantClient,
        fileCache: ConsultantFileCache = ConsultantFileCache(),
        remoteFileCacheLoader: ConsultantRemoteFileCacheLoading? = nil,
        cachePolicy: OnlineConsultantCachePolicy? = nil,
        applicationLifecycle: ConsultantApplicationLifecycle? = nil
    ) {
        self.client = client
        self.applicationLifecycle = applicationLifecycle ?? ConsultantApplicationLifecycle()
        self.contactFormActionCoordinator = ContactFormActionCoordinator(client: client)
        self.messageReadCoordinator = MessageReadCoordinator(client: client)
        self.messageSender = MessageSender(client: client)
        self.fileCache = fileCache
        self.cachePolicy = cachePolicy ?? client.config.cachePolicy
        self.remoteFileCacheLoader = remoteFileCacheLoader ?? RemoteFileCacheLoader(
            fileCache: fileCache
        )
        self.messageFileLinkCoordinator = MessageFileLinkCoordinator(
            client: client,
            fileCache: fileCache,
            remoteFileCacheLoader: self.remoteFileCacheLoader,
            cachePolicy: self.cachePolicy
        )

        trimCacheIfNeeded()
        self.applicationLifecycle.onForegroundChange = { [weak self] isInForeground in
            if isInForeground {
                self?.resumeRealtimeEventsIfNeeded()
            } else {
                self?.pauseRealtimeEvents()
            }
        }
    }

    deinit {
        startTask?.cancel()
        realtimeTask?.cancel()
        brandingLogoLoadTask?.cancel()
        Task { @MainActor [messageFileLinkCoordinator] in
            messageFileLinkCoordinator.cancel()
        }
        Task { @MainActor [messageReadCoordinator] in
            messageReadCoordinator.reset()
        }
        eventBroadcaster.finish()
        stateBroadcaster.finish()
        internalStateBroadcaster.finish()
        messageBroadcaster.finish()
        inputAttachmentBroadcaster.finish()
    }
}

// MARK: - Observation

/// Observation API for public connection and unread-message state and internal UI streams.
extension OnlineConsultantController {

    /// Returns a stream of controller events such as connection, errors, and realtime updates.
    package func events() -> AsyncStream<ControllerEvent> {
        eventBroadcaster.stream()
    }

    /// Returns a stream of connection state changes. The current state is emitted immediately.
    package func stateUpdates() -> AsyncStream<ControllerState> {
        stateBroadcaster.stream(initialValue: state)
    }

    /// Returns a stream of lifecycle states for SDK UI. The current state is emitted immediately.
    package func internalStateUpdates() -> AsyncStream<ControllerInternalState> {
        internalStateBroadcaster.stream(initialValue: internalState)
    }

    /// Returns a stream of message-list changes. The current message list is emitted immediately.
    package func messagesUpdates() -> AsyncStream<[ConsultantMessage]> {
        messageBroadcaster.stream(initialValue: messages)
    }

    /// Chat title received from backend `config.name`.
    public var name: String? {
        consultantConfig?.name
    }

    /// External consultant link settings received from the backend.
    public var linkSettings: LinkSettings {
        consultantConfig?.linkSettings ?? LinkSettings()
    }

    /// Returns a stream of input-attachment changes. The current list is emitted immediately.
    package func inputAttachmentUpdates() -> AsyncStream<[InputAttachment]> {
        inputAttachmentBroadcaster.stream(initialValue: inputAttachments)
    }
}

// MARK: - File Cache

/// File-cache API used by host applications and preview helpers to inspect, trim, clear, and populate
/// the SDK-managed local file cache.
extension OnlineConsultantController {

    /// Returns the local cached URL for a file id, if the file is already cached.
    package func cachedFileURL(fileID: String) -> URL? {
        fileCache.cachedFileURL(fileID: fileID)
    }

    /// Downloads a remote file into the local cache and returns its local URL.
    package func cacheRemoteFile(
        fileID: String,
        remoteURL: URL
    ) async throws -> URL {
        let localURL = try await remoteFileCacheLoader.cacheRemoteFile(
            fileID: fileID,
            remoteURL: remoteURL
        )
        trimCacheIfNeeded()
        return localURL
    }

    /// Returns current local file-cache statistics.
    public func cacheStatistics() -> ConsultantCacheStatistics {
        fileCache.statistics()
    }

    /// Applies the configured cache policy without blocking the main actor.
    public func trimCache() async throws -> ConsultantCacheStatistics {
        let fileCache = self.fileCache
        let cachePolicy = self.cachePolicy
        do {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try fileCache.trim(policy: cachePolicy))
                    } catch {
                        continuation.resume(throwing: ConsultantError.cacheError(from: error))
                    }
                }
            }
        } catch {
            reportError(error)
            throw error
        }
    }

    /// Clears all locally cached files without blocking the main actor.
    public func clearCache() async throws {
        messageFileLinkCoordinator.cancelRemoteCaching()
        let fileCache = self.fileCache
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try fileCache.removeAll()
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: ConsultantError.cacheError(from: error))
                    }
                }
            }
        } catch {
            reportError(error)
            throw error
        }
    }
}

/// Completion-based file-cache API.
public extension OnlineConsultantController {

    /// Applies the configured cache policy and returns statistics in the completion.
    ///
    /// - Parameters:
    ///   - completion: Receives the result of the operation.
    func trimCache(
        completion: (Result<ConsultantCacheStatistics, ConsultantError>) -> Void
    ) {
        do {
            completion(.success(try fileCache.trim(policy: cachePolicy)))
        } catch {
            let publicError = ConsultantError.cacheError(from: error)
            reportError(publicError)
            completion(.failure(publicError))
        }
    }

    /// Clears all locally cached files managed by the SDK.
    ///
    /// - Parameters:
    ///   - completion: Receives the result of the operation.
    func clearCache(completion: (Result<Void, ConsultantError>) -> Void) {
        messageFileLinkCoordinator.cancelRemoteCaching()
        do {
            try fileCache.removeAll()
            completion(.success(()))
        } catch {
            let publicError = ConsultantError.cacheError(from: error)
            reportError(publicError)
            completion(.failure(publicError))
        }
    }
}

// MARK: - Connection Lifecycle

/// Internal lifecycle used by the shared SDK session and the built-in UI retry action.
package extension OnlineConsultantController {

    func start(user: ConnectUser = ConnectUser()) {
        startTask?.cancel()
        stopRealtimeEvents()
        brandingLogoLoadTask?.cancel()
        brandingLogoLoadTask = nil
        cancelFileLinkTasks()
        messageReadCoordinator.reset()
        let generation = nextConnectionGeneration()

        startTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await performConnect(
                    user: user,
                    generation: generation
                )
            } catch {
                guard isCurrentConnectionGeneration(generation), !Task.isCancelled else { return }
                if case .failed = state { return }
                applyFailure(error)
            }
        }
    }

    private func stop() {
        startTask?.cancel()
        startTask = nil
        stopRealtimeEvents()
        brandingLogoLoadTask?.cancel()
        brandingLogoLoadTask = nil
        cancelFileLinkTasks()
        messageReadCoordinator.reset()
        nextConnectionGeneration()
        setConnectionState(.idle)
    }

    private func resetSessionState() {
        let oldUnreadIncomingMessagesCount = unreadIncomingMessagesCount
        connectResponse = nil
        isAnonymousSession = true
        messageStore.reset()
        consultantConfig = nil
        isOffline = false
        unreadIncomingMessagesCount = 0
        canLoadOlderMessages = false
        contactFormActionCoordinator.reset()
        contactFormState.reset()
        contactFormPresentation = .hidden
        _ = inputAttachmentStore.removeAll()
        emitMessages()
        emitUnreadIncomingMessagesCountIfNeeded(oldValue: oldUnreadIncomingMessagesCount)
        emitInputAttachments()
    }
}

// MARK: - Shared Session Lifecycle

extension OnlineConsultantController: SessionLifecycleListener {

    nonisolated package func sessionDidConnect(
        credentials: SessionCredentials,
        pageContext _: ConnectPageContext,
        user: ConnectUser,
        response _: ConnectResponse,
        customerIdentity _: CrmSdkCustomerIdentity?
    ) {
        Task { @MainActor [weak self] in
            self?.start(user: user)
        }
    }

    nonisolated package func sessionDidDisconnect() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            stop()
            resetSessionState()
        }
    }
}

// MARK: - Input Attachments

/// Internal input-attachment API for creating upload placeholders, uploading attachment data,
/// marking failures, and removing prepared attachments.
package extension OnlineConsultantController {

    /// Adds an attachment placeholder to the input queue.
    @discardableResult
    func addInputAttachment(
        fileName: String,
        contentType: String = "application/octet-stream",
        previewData: Data? = nil,
        messageType: String = "file"
    ) -> InputAttachment {
        let attachment = inputAttachmentStore.add(
            fileName: fileName,
            contentType: contentType,
            previewData: previewData,
            messageType: messageType
        )
        emitInputAttachments()
        return attachment
    }

    /// Uploads an existing input attachment placeholder to the backend.
    @discardableResult
    func uploadInputAttachment(
        id: UUID,
        data: Data,
        contentType: String,
        previewData: Data? = nil
    ) async throws -> InputAttachment {
        let credentials = try currentCredentials()

        updateInputAttachment(
            id: id,
            status: .uploading
        )

        if let previewData {
            updateInputAttachmentPreviewData(
                id: id,
                previewData: previewData
            )
        }

        guard let pendingAttachment = inputAttachmentStore.attachment(id: id) else {
            throw ConsultantControllerError.inputAttachmentRemoved
        }

        do {
            let response = try await client.uploadFile(
                data: data,
                contentType: contentType,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )

            guard let fileID = response.id else {
                throw ConsultantControllerError.missingUploadedFileID
            }

            do {
                try fileCache.store(
                    data: data,
                    fileID: fileID.value,
                    contentType: contentType
                )
            } catch {
                reportError(ConsultantError.cacheError(from: error))
            }
            trimCacheIfNeeded()

            let uploadedAttachment = updateInputAttachment(
                id: id,
                status: .uploaded(fileID: fileID)
            ) ?? pendingAttachment.updatingStatus(.uploaded(fileID: fileID))

            return uploadedAttachment
        } catch {
            updateInputAttachment(
                id: id,
                status: .failed(message: error.localizedDescription)
            )
            reportError(error)
            throw error
        }
    }

    /// Marks an input attachment as failed.
    func failInputAttachment(
        id: UUID,
        message: String
    ) {
        updateInputAttachment(
            id: id,
            status: .failed(message: message)
        )
    }

    /// Removes an attachment from the input queue.
    func removeInputAttachment(id: UUID) {
        guard inputAttachmentStore.remove(id: id) else {
            return
        }

        emitInputAttachments()
    }

    private func removeInputAttachments(ids: [UUID]) {
        guard inputAttachmentStore.remove(ids: ids) else {
            return
        }

        emitInputAttachments()
    }
}

// MARK: - Message Sending

/// Internal message sending API for visitor text messages and messages with already uploaded input
/// attachments.
package extension OnlineConsultantController {

    /// Retries a failed outgoing message. Repeated requests while it is sending are ignored.
    func retryMessage(id: String) async throws {
        guard let message = messageStore.message(id: id), message.canRetrySending else { return }
        let credentials = try currentCredentials()
        try await messageSender.retryMessage(
            message,
            credentials: MessageSendCredentials(
                sessionID: credentials.sessionID,
                userToken: credentials.userToken
            ),
            callbacks: messageSenderCallbacks()
        )
    }

    /// Sends a visitor text message.
    func sendMessage(_ text: String) async throws {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let credentials = try currentCredentials()
        try await messageSender.sendTextMessage(
            messageText,
            credentials: MessageSendCredentials(
                sessionID: credentials.sessionID,
                userToken: credentials.userToken
            ),
            callbacks: messageSenderCallbacks()
        )
    }

    /// Sends visitor text together with already uploaded input attachments.
    func sendMessage(
        _ text: String,
        attachments: [InputAttachment]
    ) async throws {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !attachments.isEmpty else {
            try await sendMessage(messageText)
            return
        }

        let credentials = try currentCredentials()
        try await messageSender.sendAttachmentMessages(
            text: messageText,
            attachments: attachments,
            credentials: MessageSendCredentials(
                sessionID: credentials.sessionID,
                userToken: credentials.userToken
            ),
            callbacks: messageSenderCallbacks()
        )
    }
}

// MARK: - Contact Form Submission

/// Internal contact-form submission API and related submit result handling.
package extension OnlineConsultantController {

    /// Submits the currently displayed contact form.
    func submitContactForm(_ data: ContactFormSubmitData) async throws {
        switch data.kind {
        case .contact:
            try await submitContactFormData(data)
        case .offline:
            try await submitOfflineFormData(data)
        }
    }

    private func submitContactFormData(_ data: ContactFormSubmitData) async throws {
        clearActionContactFormSubmitError(actionID: data.actionID)

        do {
            let credentials = try currentCredentials()
            try await client.sendContactForm(
                data,
                session: credentials.sessionID,
                userToken: credentials.userToken,
                actionID: data.actionID?.value
            )
            emit(.contactFormSubmitted(data))
            applyContactFormSubmitData(data)
            markActionContactFormSubmitted(actionID: data.actionID)
        } catch {
            markActionContactFormSubmitError(
                actionID: data.actionID,
                message: error.localizedDescription,
                submittedFields: data.submittedFields
            )
            reportError(error)
            throw error
        }
    }

    private func submitOfflineFormData(_ data: ContactFormSubmitData) async throws {
        clearOfflineContactFormSubmitError()

        do {
            let credentials = try currentCredentials()
            try await client.sendOfflineForm(
                data,
                session: credentials.sessionID,
                userToken: credentials.userToken
            )
            emit(.contactFormSubmitted(data))
            applyOfflineFormSubmitData(data)
            markOfflineContactFormSubmitted()
        } catch {
            markOfflineContactFormSubmitError(
                message: error.localizedDescription,
                submittedFields: data.submittedFields
            )
            reportError(error)
            throw error
        }
    }
}

// MARK: - Message Loading

/// Internal message history loading API for reloading the latest page and requesting older pages.
package extension OnlineConsultantController {

    /// Loads older messages using the current message count as an offset.
    @discardableResult
    func loadOlderMessages() async throws -> MessagesPage {
        let credentials = try currentCredentials()
        let generation = connectionGeneration
        let loadedMessages = try await client.loadMessages(
            session: credentials.sessionID,
            userToken: credentials.userToken,
            offset: messageStore.messageCount
        )
        try Task.checkCancellation()
        guard isCurrentConnectionGeneration(generation) else { throw CancellationError() }
        canLoadOlderMessages = loadedMessages.count >= client.messagesPageSize
        mergeMessages(loadedMessages)
        return MessagesPage(
            messages: loadedMessages,
            hasMoreMessages: canLoadOlderMessages
        )
    }
}

// MARK: - Connection Flow

/// Internal connect flow that calls the backend, validates credentials, applies bootstrap state,
/// loads additional initial messages, applies contact-form actions, and subscribes to realtime events.
package extension OnlineConsultantController {

    private func performConnect(
        user: ConnectUser,
        generation: UUID
    ) async throws -> ConsultantConnectResponse {
        setConnectionState(.connecting)

        do {
            let response = try await client.connect()
            try ensureCurrentConnectionGeneration(generation)
            let isAnonymous = await client.isAnonymousSession()
            try ensureCurrentConnectionGeneration(generation)
            isAnonymousSession = isAnonymous
            try applyConnectResponse(response, requestedUser: user, publishesReady: false)
            brandingLogoLoadTask = FooterBrandingLogoLoader.prefetch(
                domainConfig: response.config?.domainConfig,
                theme: ConsultantTheme(config: response.config)
            )
            await loadInitialMessagesIfNeeded(
                connectResponse: response,
                generation: generation
            )
            try ensureCurrentConnectionGeneration(generation)
            applyInitialContactFormActionIfNeeded(response.actions, generation: generation)
            refreshVirtualSupportMessages()
            publishReadyState()
            emit(.connected(response))
            emitMessages()
            subscribeRealtimeEvents(generation: generation)
            return response
        } catch {
            guard isCurrentConnectionGeneration(generation), !Task.isCancelled else { throw error }
            applyFailure(error)
            throw error
        }
    }

    private func applyConnectResponse(
        _ response: ConsultantConnectResponse,
        requestedUser: ConnectUser,
        publishesReady: Bool = true
    ) throws {
        guard response.user.token != nil, response.session.id?.value != nil else {
            throw ConsultantControllerError.missingCredentials
        }

        guard response.behaviour?.widget != false else {
            throw ConsultantControllerError.unavailable
        }

        connectResponse = response
        contactFormState.applyConnectedUser(
            response.user,
            fallbackUser: requestedUser
        )
        consultantConfig = response.config
        isOffline = response.behaviour?.isOffline == true
        canLoadOlderMessages = !response.messages.isEmpty
        applyMessages(response.messages, emitsEvent: false, publishesReady: publishesReady)

        if publishesReady {
            emit(.connected(response))
            emitMessages()
        }
    }

    private func loadInitialMessagesIfNeeded(
        connectResponse response: ConsultantConnectResponse,
        generation: UUID
    ) async {
        let alreadyLoadedCount = response.messages.count
        let initialMessagesLimit = client.initialMessagesLimit

        guard initialMessagesLimit > alreadyLoadedCount else {
            canLoadOlderMessages = alreadyLoadedCount > 0
            return
        }

        guard let userToken = response.user.token,
              let sessionID = response.session.id?.value else {
            canLoadOlderMessages = false
            return
        }

        let requestLimit = initialMessagesLimit - alreadyLoadedCount

        do {
            let loadedMessages = try await client.loadMessages(
                session: sessionID,
                userToken: userToken,
                limit: requestLimit,
                offset: alreadyLoadedCount
            )
            guard isCurrentConnectionGeneration(generation), !Task.isCancelled else {
                return
            }
            canLoadOlderMessages = loadedMessages.count >= requestLimit
            mergeMessages(loadedMessages, emitsEvent: false, publishesReady: false)
        } catch {
            guard isCurrentConnectionGeneration(generation), !Task.isCancelled else { return }
            canLoadOlderMessages = alreadyLoadedCount > 0
            reportError(error)
        }
    }
}

// MARK: - Contact-Form Actions

/// Displays contact-form actions and refreshes local intro and offline messages.
package extension OnlineConsultantController {

    private func applyInitialContactFormActionIfNeeded(
        _ actions: [SiteAction],
        generation: UUID
    ) {
        guard let contactFormMessage = contactFormActionCoordinator.initialContactFormMessageIfNeeded(
            actions: actions,
            contactFormUser: contactFormState.user,
            messagesAreEmpty: messageStore.isEmpty,
            generation: generation,
            isCurrentGeneration: { [weak self] generation in
                self?.isCurrentConnectionGeneration(generation) == true
            },
            currentCredentials: { [weak self] in
                guard let self else {
                    throw ConsultantControllerError.missingCredentials
                }

                return try self.currentCredentials()
            },
            handleError: { [weak self] error in
                self?.reportError(error)
            }
        ) else { return }

        messageStore.append(contentsOf: [contactFormMessage])
        recalculateUnreadIncomingMessagesCount()
        recalculateContactFormPresentation()
        resolveMissingFileLinks()
    }

    @discardableResult
    private func refreshVirtualSupportMessages() -> Bool {
        guard messageStore.refreshVirtualSupportMessages(
            config: consultantConfig,
            user: contactFormState.user,
            isOffline: isOffline,
            hasSubmittedOfflineForm: contactFormState.hasSubmittedForm(kind: .offline)
        ) else {
            return false
        }

        recalculateUnreadIncomingMessagesCount()
        recalculateContactFormPresentation()
        return true
    }
}

// MARK: - Realtime

/// Internal realtime handling for WebSocket subscription, reconnects, decoded event application, and
/// incoming-message notifications.
package extension OnlineConsultantController {

    private func subscribeRealtimeEvents(generation: UUID) {
        pauseRealtimeEvents()
        realtimeSessionGeneration = generation
        resumeRealtimeEventsIfNeeded()
    }

    private func stopRealtimeEvents() {
        realtimeSessionGeneration = nil
        pauseRealtimeEvents()
    }

    private func pauseRealtimeEvents() {
        realtimeGeneration = UUID()
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func resumeRealtimeEventsIfNeeded() {
        guard applicationLifecycle.isInForeground,
              realtimeTask == nil,
              let generation = realtimeSessionGeneration,
              isCurrentConnectionGeneration(generation) else { return }
        let realtimeGeneration = UUID()
        self.realtimeGeneration = realtimeGeneration
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.realtimeGeneration == realtimeGeneration { realtimeTask = nil }
            }

            while isCurrentConnectionGeneration(generation),
                  self.realtimeGeneration == realtimeGeneration,
                  applicationLifecycle.isInForeground, !Task.isCancelled {
                do {
                    let credentials = try currentCredentials()
                    let stream = client.subscribeRealtimeEvents(
                        session: credentials.sessionID,
                        userToken: credentials.userToken,
                        updatedAt: messageStore.latestKnownUpdatedAt
                    )

                    for try await event in stream {
                        guard isCurrentConnectionGeneration(generation),
                              self.realtimeGeneration == realtimeGeneration,
                              applicationLifecycle.isInForeground, !Task.isCancelled else {
                            return
                        }
                        applyRealtimeEvent(event)
                    }

                    return
                } catch {
                    guard isCurrentConnectionGeneration(generation),
                          self.realtimeGeneration == realtimeGeneration,
                          applicationLifecycle.isInForeground, !Task.isCancelled else { return }

                    reportError(error)

                    guard client.config.autoReconnectWebSocket else {
                        return
                    }

                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(client.config.webSocketReconnectDelay * 1_000_000_000)
                        )
                    } catch { return }
                }
            }
        }
    }

    private func applyRealtimeEvent(_ event: ConsultantRealtimeEvent) {
        emit(.realtimeEvent(event))

        switch event {
        case .message(let message):
            messageStore.applyRealtimeMessage(message)
            publishMessagesChanged()
        case .offlineStatus(let status):
            isOffline = status.isOffline
            let didRefreshMessages = refreshVirtualSupportMessages()
            if !didRefreshMessages {
                recalculateContactFormPresentation()
            }
            publishReadyState()
            if didRefreshMessages {
                emitMessages()
            }
            emit(.offlineStatusChanged(status.isOffline))
        case .unknown:
            break
        }
    }
}

// MARK: - Message State

/// Internal message-state mutations shared by connect, history loading, realtime events, outgoing
/// sends, file-link updates, and contact-form updates.
package extension OnlineConsultantController {

    private func applyMessages(
        _ value: [ConsultantMessage],
        emitsEvent: Bool = true,
        publishesReady: Bool = true
    ) {
        messageStore.replaceAll(value)
        publishMessagesChanged(
            emitsEvent: emitsEvent,
            publishesReady: publishesReady,
            fileLinkResolution: .beforeEmission
        )
    }

    private func mergeMessages(
        _ value: [ConsultantMessage],
        emitsEvent: Bool = true,
        publishesReady: Bool = true
    ) {
        messageStore.merge(value)
        publishMessagesChanged(
            emitsEvent: emitsEvent,
            publishesReady: publishesReady,
            fileLinkResolution: .beforeEmission
        )
    }

    private func appendLocalOutgoingMessage(
        _ text: String,
        messageType: MessageType = .text,
        items: [MessageItem]? = nil
    ) -> String {
        let id = messageStore.appendLocalOutgoingMessage(
            text,
            messageType: messageType,
            items: items
        )
        publishMessagesChanged()

        return id
    }

    private func replaceLocalMessage(
        id: String,
        sentMessage: ConsultantSentMessage
    ) {
        if messageStore.replaceLocalMessage(id: id, sentMessage: sentMessage) {
            publishMessagesChanged()
        }
    }

    private func updateLocalMessageStatus(id: String, status: MessageStatus) {
        if messageStore.updateLocalMessageStatus(id: id, status: status) {
            publishMessagesChanged()
        }
    }

    /// Marks incoming messages up to a backend message id as read locally and schedules backend sync.
    @discardableResult
    func markIncomingMessagesRead(upTo messageID: String) -> Bool {
        let credentials: (sessionID: String, userToken: String)
        do {
            credentials = try currentCredentials()
        } catch {
            reportError(error)
            return false
        }

        guard messageStore.markIncomingMessagesSeen(upTo: messageID) else {
            return false
        }

        publishMessagesChanged(fileLinkResolution: .none)
        messageReadCoordinator.schedule(
            messageID: messageID,
            session: credentials.sessionID,
            userToken: credentials.userToken,
            handleError: { [weak self] error in
                self?.reportError(error)
            }
        )
        return true
    }

    private func messageSenderCallbacks() -> MessageSenderCallbacks {
        .init(
            appendLocalMessage: { [weak self] text, messageType, items in
                self?.appendLocalOutgoingMessage(
                    text,
                    messageType: messageType,
                    items: items
                ) ?? ""
            },
            removeInputAttachments: { [weak self] attachmentIDs in
                self?.removeInputAttachments(ids: attachmentIDs)
            },
            replaceLocalMessage: { [weak self] localMessageID, sentMessage in
                self?.replaceLocalMessage(
                    id: localMessageID,
                    sentMessage: sentMessage
                )
            },
            updateLocalMessageStatus: { [weak self] localMessageID, status in
                self?.updateLocalMessageStatus(
                    id: localMessageID,
                    status: status
                )
            },
            handleError: { [weak self] error in
                self?.reportError(error)
            }
        )
    }

    private enum FileLinkResolutionTiming {
        case beforeEmission
        case afterEmission
        case none
    }

    private func publishMessagesChanged(
        emitsEvent: Bool = true,
        publishesReady: Bool = true,
        fileLinkResolution: FileLinkResolutionTiming = .afterEmission
    ) {
        recalculateUnreadIncomingMessagesCount()
        recalculateContactFormPresentation()
        if publishesReady {
            publishReadyState()
        }
        if case .beforeEmission = fileLinkResolution {
            resolveMissingFileLinks()
        }
        if emitsEvent {
            emitMessages()
        }
        if case .afterEmission = fileLinkResolution {
            resolveMissingFileLinks()
        }
    }
}

// MARK: - File Links

/// Internal file-link resolution that applies cached URLs, requests missing backend links, and
/// coordinates background remote-file caching.
package extension OnlineConsultantController {

    private func resolveMissingFileLinks() {
        let credentials = try? currentCredentials()
        messageFileLinkCoordinator.resolveMissingFileLinks(
            unresolvedFileIDs: messageStore.unresolvedFileLinkItemIDs,
            credentials: credentials.map {
                MessageFileLinkCredentials(
                    sessionID: $0.sessionID,
                    userToken: $0.userToken
                )
            },
            applyFileLinks: { [weak self] links in
                self?.applyFileLinks(links)
            },
            handleError: { [weak self] error in
                self?.reportError(error)
            }
        )
    }

    private func trimCacheIfNeeded() {
        guard cachePolicy.automaticCleanup else {
            return
        }

        do {
            _ = try fileCache.trim(policy: cachePolicy)
        } catch {
            reportError(ConsultantError.cacheError(from: error))
        }
    }

    private func applyFileLinks(_ links: [String: String]) {
        guard messageStore.applyFileLinks(links) else {
            return
        }

        publishMessagesChanged(fileLinkResolution: .none)
    }

    private func cancelFileLinkTasks() {
        messageFileLinkCoordinator.cancel()
    }
}

// MARK: - Unread State

/// Internal unread incoming-message badge calculation and publishing.
package extension OnlineConsultantController {

    private func recalculateUnreadIncomingMessagesCount() {
        let oldValue = unreadIncomingMessagesCount

        guard connectResponse?.config?.useUnreadCounter != false else {
            unreadIncomingMessagesCount = 0
            emitUnreadIncomingMessagesCountIfNeeded(oldValue: oldValue)
            return
        }

        unreadIncomingMessagesCount = messageStore.unreadIncomingMessagesCount
        emitUnreadIncomingMessagesCountIfNeeded(oldValue: oldValue)
    }
}

// MARK: - Contact Form State

/// Internal contact-form presentation state, submit-state updates, and per-message form error
/// handling.
package extension OnlineConsultantController {

    private func recalculateContactFormPresentation() {
        contactFormPresentation = contactFormState.presentation(
            response: connectResponse,
            messages: messages,
            isOffline: isOffline
        )
    }

    private func applyContactFormSubmitData(_ data: ContactFormSubmitData) {
        contactFormState.applySubmitData(data)
        connectResponse = connectResponse?.applyingContactFormSubmitData(data)
        recalculateContactFormPresentation()
        publishReadyState()
    }

    private func applyOfflineFormSubmitData(_ data: ContactFormSubmitData) {
        contactFormState.applySubmitData(data, kind: .offline)
        connectResponse = connectResponse?.applyingContactFormSubmitData(data)
        recalculateContactFormPresentation()
        publishReadyState()
    }

    private func markActionContactFormSubmitted(actionID: FlexibleID?) {
        guard messageStore.markActionContactFormSubmitted(actionID: actionID) else {
            return
        }

        publishMessagesChanged(fileLinkResolution: .none)
    }

    private func markOfflineContactFormSubmitted() {
        guard messageStore.markOfflineContactFormSubmitted() else {
            return
        }

        publishMessagesChanged(fileLinkResolution: .none)
    }

    private func clearActionContactFormSubmitError(actionID: FlexibleID?) {
        updateActionContactForm(actionID: actionID) { $0.clearingSubmitError() }
    }

    private func clearOfflineContactFormSubmitError() {
        updateOfflineContactForm { $0.clearingSubmitError() }
    }

    private func markActionContactFormSubmitError(
        actionID: FlexibleID?,
        message: String,
        submittedFields: [String: String]
    ) {
        updateActionContactForm(actionID: actionID) {
            $0.applyingSubmitError(
                message,
                submittedFields: submittedFields
            )
        }
    }

    private func markOfflineContactFormSubmitError(
        message: String,
        submittedFields: [String: String]
    ) {
        updateOfflineContactForm {
            $0.applyingSubmitError(
                message,
                submittedFields: submittedFields
            )
        }
    }

    private func updateActionContactForm(
        actionID: FlexibleID?,
        transform: (ContactForm) -> ContactForm
    ) {
        guard messageStore.updateActionContactForm(actionID: actionID, transform: transform) else {
            return
        }

        publishMessagesChanged(fileLinkResolution: .none)
    }

    private func updateOfflineContactForm(transform: (ContactForm) -> ContactForm) {
        guard messageStore.updateOfflineContactForm(transform: transform) else {
            return
        }

        publishMessagesChanged(fileLinkResolution: .none)
    }
}

// MARK: - State And Events

/// Internal controller state publication, generation validation, credential lookup, and event
/// broadcasting helpers.
package extension OnlineConsultantController {

    private func publishReadyState() {
        guard let snapshot = makeSnapshot() else { return }

        setInternalState(.ready(snapshot))
        let readyState = ControllerState.ready(isAnonymous: isAnonymousSession)
        if state != readyState {
            setConnectionState(readyState)
        }
    }

    private func makeSnapshot() -> ControllerSnapshot? {
        guard let connectResponse else { return nil }

        return .init(
            connectResponse: connectResponse,
            userToken: connectResponse.user.token,
            sessionID: connectResponse.session.id?.value,
            messages: messages,
            consultantConfig: consultantConfig,
            isOffline: isOffline,
            blocksMessageInput: isOffline && connectResponse.config?.useOfflineMode == true,
            unreadIncomingMessagesCount: unreadIncomingMessagesCount,
            canLoadOlderMessages: canLoadOlderMessages,
            contactFormPresentation: contactFormPresentation
        )
    }

    private func setConnectionState(_ newState: ControllerState) {
        state = newState
        stateBroadcaster.yield(newState)
        onStateChange?(newState)
        emit(.stateChanged(newState))

        switch newState {
        case .idle:
            setInternalState(.idle)
        case .connecting:
            setInternalState(.connecting)
        case .ready:
            break
        case .failed(let error):
            setInternalState(.failed(error.localizedDescription))
        }
    }

    private func setInternalState(_ newState: ControllerInternalState) {
        internalState = newState
        internalStateBroadcaster.yield(newState)
    }

    private func emit(_ event: ControllerEvent) {
        eventBroadcaster.yield(event)
    }

    private func applyFailure(_ error: Error) {
        let publicError = ConsultantError.from(error)
        setConnectionState(.failed(publicError))
        emit(.error(publicError.localizedDescription))
    }

    func reportError(_ error: Error) {
        let publicError = ConsultantError.from(error)
        emit(.error(publicError.localizedDescription))
    }

    @discardableResult
    private func nextConnectionGeneration() -> UUID {
        connectionGeneration = UUID()
        return connectionGeneration
    }

    private func ensureCurrentConnectionGeneration(_ generation: UUID) throws {
        guard isCurrentConnectionGeneration(generation), !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func isCurrentConnectionGeneration(_ generation: UUID) -> Bool {
        connectionGeneration == generation
    }

    private func currentCredentials() throws -> (sessionID: String, userToken: String) {
        guard
            let userToken = connectResponse?.user.token,
            let sessionID = connectResponse?.session.id?.value
        else {
            throw ConsultantControllerError.notConnected
        }

        return (sessionID, userToken)
    }

    private func emitMessages() {
        messageBroadcaster.yield(messages)
    }

    private func emitUnreadIncomingMessagesCountIfNeeded(oldValue: Int) {
        guard unreadIncomingMessagesCount != oldValue else { return }

        emit(.unreadIncomingMessagesCountChanged(unreadIncomingMessagesCount))
        onUnreadIncomingMessagesCountChange?(unreadIncomingMessagesCount)
    }
}

// MARK: - Input Attachment State

/// Internal mutation helpers for input attachment status, preview data, and input attachment stream
/// events.
package extension OnlineConsultantController {

    @discardableResult
    private func updateInputAttachment(
        id: UUID,
        status: InputAttachmentStatus
    ) -> InputAttachment? {
        let oldAttachment = inputAttachmentStore.attachment(id: id)
        let attachment = inputAttachmentStore.updateStatus(
            id: id,
            status: status
        )

        guard attachment != oldAttachment else {
            return attachment
        }

        emitInputAttachments()
        return attachment
    }

    private func updateInputAttachmentPreviewData(
        id: UUID,
        previewData: Data
    ) {
        guard inputAttachmentStore.updatePreviewData(id: id, previewData: previewData) else {
            return
        }

        emitInputAttachments()
    }

    private func emitInputAttachments() {
        inputAttachmentBroadcaster.yield(inputAttachments)
    }
}
