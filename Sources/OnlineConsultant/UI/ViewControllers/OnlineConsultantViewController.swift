import Core
import UIKit

/// Ready-to-use chat screen backed by the shared `OnlineConsultantController`.
///
/// The view controller owns message rendering, input attachment picking and upload,
/// message attachment previews, contact form submission, pagination, and user-facing errors.
@MainActor
public final class OnlineConsultantViewController: UIViewController {

    /// Root chat view managed by the view controller.
    package private(set) lazy var consultantView: ConsultantView = {
        ConsultantView()
    }()

    private let inputBarAttachmentCoordinator = InputBarAttachmentCoordinator()
    private let messageAttachmentCoordinator = MessageAttachmentCoordinator()
    private var controller: OnlineConsultantController
    private var stateTask: Task<Void, Never>?
    private var messagesTask: Task<Void, Never>?
    private var inputAttachmentsTask: Task<Void, Never>?
    private var historyCoordinator: MessageHistoryCoordinator?
    private var quoteNavigationTask: Task<Void, Never>?
    private var quoteNavigationID: String?
    private var quoteNavigationRequestID: UUID?
    private var loadOlderMessagesTask: Task<Void, Never>?
    private var didReachStartOfHistory = false
    private var isChatVisible = false

    /// Creates a chat screen backed by the process-wide online consultant module.
    public convenience init() {
        self.init(controller: CrmSdk.shared.onlineConsultant)
    }

    package init(controller: OnlineConsultantController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Installs `consultantView` as the root view.
    public override func loadView() {
        view = consultantView
    }

    /// Configures coordinators, view callbacks, and starts controller binding when available.
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupInputBarAttachmentCoordinator()
        setupMessageAttachmentCoordinator()
        setupConsultantViewCallbacks()
        startControllerBinding()
    }

    /// Marks the chat screen as visible and refreshes message read state.
    ///
    /// - Parameters:
    ///   - animated: Whether the appearance transition is animated.
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isChatVisible = true
        consultantView.markVisibleIncomingMessagesReadIfNeeded()
        consultantView.scheduleVisibleIncomingMessagesReadCheck()
    }

    /// Stops treating the chat screen as visible.
    ///
    /// - Parameters:
    ///   - animated: Whether the appearance transition is animated.
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isChatVisible = false
        quoteNavigationTask?.cancel()
        quoteNavigationTask = nil
        quoteNavigationID = nil
        quoteNavigationRequestID = nil
    }

    deinit {
        stateTask?.cancel()
        messagesTask?.cancel()
        inputAttachmentsTask?.cancel()
        quoteNavigationTask?.cancel()
        loadOlderMessagesTask?.cancel()
    }

    /// Updates the chat title after its parent controller changes.
    ///
    /// - Parameters:
    ///   - parent: New parent view controller, or `nil` when removed.
    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyControllerTitle(title)
    }

    private func setupInputBarAttachmentCoordinator() {
        inputBarAttachmentCoordinator.presentingViewController = self
        inputBarAttachmentCoordinator.onError = { [weak self] error in
            self?.controller.reportError(error)
            self?.showError(error)
        }
        inputBarAttachmentCoordinator.onAlert = { [weak self] title, message in
            self?.controller.reportError(ConsultantError.attachment(.operationFailed(message)))
            self?.showErrorAlert(title: title, message: message)
        }
    }

    private func setupMessageAttachmentCoordinator() {
        messageAttachmentCoordinator.presentingViewController = self
        messageAttachmentCoordinator.onError = { [weak self] error in
            self?.controller.reportError(error)
            self?.showError(error)
        }
        messageAttachmentCoordinator.onLoadingFilePreviewIDsChange = { [weak self] fileIDs in
            self?.consultantView.setLoadingFilePreviewIDs(fileIDs)
        }
        messageAttachmentCoordinator.onLoadingImagePreviewIDsChange = { [weak self] fileIDs in
            self?.consultantView.setLoadingImagePreviewIDs(fileIDs)
        }
    }

    private func setupConsultantViewCallbacks() {
        consultantView.onSendMessage = { [weak self] text in
            self?.sendMessage(text)
        }
        consultantView.onRetryMessage = { [weak self] id in
            self?.retryMessage(id: id)
        }
        consultantView.onOpenAttachmentMenu = { [weak self] sourceView in
            self?.inputBarAttachmentCoordinator.showAttachmentMenu(sourceView: sourceView)
        }
        consultantView.onRemoveInputAttachment = { [weak self] id in
            self?.inputBarAttachmentCoordinator.removeInputAttachment(id: id)
        }
        consultantView.onRetryInputAttachment = { [weak self] id in
            self?.inputBarAttachmentCoordinator.retryInputAttachment(id: id)
        }
        consultantView.onContactFormSubmit = { [weak self] data in
            self?.submitContactForm(data)
        }
        consultantView.onQuoteTap = { [weak self] id in self?.navigateToQuote(id: id) }
        consultantView.onLoadOlderMessages = { [weak self] in
            self?.loadOlderMessages()
        }
        consultantView.onImagePreview = { [weak self] items, startIndex in
            self?.messageAttachmentCoordinator.showImagePreview(items: items, startIndex: startIndex)
        }
        consultantView.onFilePreview = { [weak self] items, startIndex in
            self?.messageAttachmentCoordinator.showFilePreview(items: items, startIndex: startIndex)
        }
        consultantView.onMessageLinkTap = { [weak self] url in
            self?.openLink(url)
        }
        consultantView.onAgreementTap = { [weak self] url in
            self?.openLink(url)
        }
        consultantView.onBrandingFooterTap = { [weak self] url in
            self?.openLink(url)
        }
        consultantView.onVisibleIncomingMessagesRead = { [weak self] messageID in
            self?.markIncomingMessagesRead(upTo: messageID) == true
        }
        consultantView.onStateRetry = { [weak self] in
            self?.controller.start()
        }
    }

    private func markIncomingMessagesRead(upTo messageID: String) -> Bool {
        guard isChatVisible else {
            return false
        }
        return controller.markIncomingMessagesRead(upTo: messageID)
    }

    private func startControllerBinding() {
        cancelBindingTasks()
        resetBindingState()
        historyCoordinator = MessageHistoryCoordinator(
            messages: { [controller] in controller.messages },
            canLoadMore: { [controller] in controller.canLoadOlderMessages },
            loadPage: { [weak self, controller] in
                let page = try await controller.loadOlderMessages()
                if !page.hasMoreMessages {
                    self?.didReachStartOfHistory = true
                    self?.consultantView.setCanLoadOlderMessages(false)
                }
                return page
            }
        )
        inputBarAttachmentCoordinator.setController(controller)
        messageAttachmentCoordinator.setController(controller)
        consultantView.setCanLoadOlderMessages(true)
        let blocksMessageInput = controller.isOffline
            && controller.consultantConfig?.useOfflineMode == true
        consultantView.setInputBarHidden(blocksMessageInput)
        consultantView.setCanSendMessages(!blocksMessageInput)
        setConsultantConfig(controller.consultantConfig)
        consultantView.setContactFormPresentation(controller.contactFormPresentation)
        consultantView.setMessages(controller.messages)
        consultantView.setInputAttachments(controller.inputAttachments)
        apply(controller.internalState)

        stateTask = Task { [weak self, controller] in
            for await state in controller.internalStateUpdates() {
                guard !Task.isCancelled else { return }
                self?.apply(state)
            }
        }

        messagesTask = Task { [weak self, controller] in
            for await messages in controller.messagesUpdates() {
                guard !Task.isCancelled else { return }
                self?.consultantView.setMessages(messages)
            }
        }

        inputAttachmentsTask = Task { [weak self, controller] in
            for await attachments in controller.inputAttachmentUpdates() {
                guard !Task.isCancelled else { return }
                self?.inputBarAttachmentCoordinator.pruneUploadPayloads(keeping: attachments)
                self?.consultantView.setInputAttachments(attachments)
            }
        }
    }

    private func setConsultantConfig(_ config: ConsultantConfig?) {
        consultantView.setConsultantConfig(config)
        applyNavigationBarAppearance(config: config)
        applyControllerTitle(config?.name)
    }

    private func applyNavigationBarAppearance(config: ConsultantConfig?) {
        let theme = ConsultantTheme(config: config)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = theme.brandColor
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: theme.mainTextColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: theme.mainTextColor]

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    private func applyControllerTitle(_ title: String?) {
        self.title = title
    }

    private func cancelBindingTasks() {
        stateTask?.cancel()
        messagesTask?.cancel()
        inputAttachmentsTask?.cancel()
        inputBarAttachmentCoordinator.cancelTasks()
        loadOlderMessagesTask?.cancel()
        quoteNavigationTask?.cancel()
        historyCoordinator?.cancel()
        historyCoordinator = nil
        quoteNavigationTask = nil
        quoteNavigationID = nil
        quoteNavigationRequestID = nil
        messageAttachmentCoordinator.cancelTasks()

        stateTask = nil
        messagesTask = nil
        inputAttachmentsTask = nil
        loadOlderMessagesTask = nil
    }

    private func resetBindingState() {
        inputBarAttachmentCoordinator.resetState()
        messageAttachmentCoordinator.resetState()
        consultantView.setLoadingOlderMessages(false)
        consultantView.setContactFormSubmitting(false)
        didReachStartOfHistory = false
    }

    private func openLink(_ url: URL) {
        guard url.scheme?.isEmpty == false else {
            return
        }

        UIApplication.shared.open(url, options: [:])
    }

    private func sendMessage(_ text: String) {
        let attachments = controller.inputAttachments
        consultantView.clearMessageInput()
        inputBarAttachmentCoordinator.clearUploadPayloads(for: attachments)
        Task { [controller, attachments] in
            // The controller reports errors and keeps failed messages available for retry.
            try? await controller.sendMessage(text, attachments: attachments)
        }
    }

    private func retryMessage(id: String) {
        Task { [controller] in
            try? await controller.retryMessage(id: id)
        }
    }

    private func showError(_ error: Error) {
        showErrorAlert(
            title: ConsultantLocalization.commonError.localized,
            message: error.localizedDescription
        )
    }

    private func submitContactForm(_ data: ContactFormSubmitData) {
        consultantView.setContactFormSubmitting(true)
        Task { [weak self, controller] in
            defer {
                if let self, self.controller === controller {
                    self.consultantView.setContactFormSubmitting(false)
                }
            }

            do {
                try await controller.submitContactForm(data)
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, self.controller === controller else { return }
                self.showContactFormSubmitError(error)
            }
        }
    }

    private func showContactFormSubmitError(_ error: Error) {
        consultantView.setContactFormSubmitError(error.localizedDescription)
    }

    private func showErrorAlert(title: String, message: String) {
        guard isViewLoaded, view.window != nil else {
            return
        }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: ConsultantLocalization.commonOk.localized,
            style: .default
        ))

        present(alert, animated: true)
    }

    private func navigateToQuote(id: String) {
        guard quoteNavigationID != id, let historyCoordinator else { return }
        quoteNavigationTask?.cancel()
        quoteNavigationID = id
        let requestID = UUID()
        quoteNavigationRequestID = requestID
        quoteNavigationTask = Task { [weak self, controller, historyCoordinator] in
            defer {
                if self?.quoteNavigationRequestID == requestID {
                    self?.quoteNavigationID = nil
                    self?.quoteNavigationRequestID = nil
                    self?.quoteNavigationTask = nil
                }
            }
            do {
                let found = try await historyCoordinator.findMessage(id: id)
                try Task.checkCancellation()
                guard let self, self.controller === controller else { return }
                if found {
                    self.consultantView.setMessages(controller.messages)
                    self.consultantView.revealMessage(id: id)
                } else {
                    let alert = UIAlertController(
                        title: nil, message: ConsultantLocalization.messageQuoteUnavailable.localized,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: ConsultantLocalization.commonOk.localized, style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self?.showError(error)
            }
        }
    }

    private func loadOlderMessages() {
        guard loadOlderMessagesTask == nil, let historyCoordinator else {
            return
        }

        consultantView.setLoadingOlderMessages(true)
        loadOlderMessagesTask = Task { [weak self, historyCoordinator] in
            defer {
                self?.consultantView.setLoadingOlderMessages(false)
                self?.loadOlderMessagesTask = nil
            }

            do {
                let olderMessagesPage = try await historyCoordinator.loadNextPage()
                if !olderMessagesPage.hasMoreMessages {
                    self?.didReachStartOfHistory = true
                    self?.consultantView.setCanLoadOlderMessages(false)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.consultantView.setCanLoadOlderMessages(self?.didReachStartOfHistory == false)
            }
        }
    }

    private func apply(_ state: ControllerInternalState) {
        switch state {
        case .ready(let snapshot):
            consultantView.setStateViewMode(.hidden)
            didReachStartOfHistory = !snapshot.canLoadOlderMessages
            consultantView.setInputBarHidden(snapshot.blocksMessageInput)
            consultantView.setCanSendMessages(!snapshot.blocksMessageInput)
            consultantView.setCanLoadOlderMessages(snapshot.canLoadOlderMessages)
            setConsultantConfig(snapshot.consultantConfig)
            consultantView.setContactFormPresentation(snapshot.contactFormPresentation)
        case .idle:
            applyInactiveState(viewMode: .hidden)
        case .connecting:
            applyInactiveState(viewMode: .loading)
        case .failed:
            applyInactiveState(viewMode: .error)
        }
    }

    private func applyInactiveState(viewMode: ConsultantStateView.Mode) {
        consultantView.setStateViewMode(viewMode)
        didReachStartOfHistory = false
        setConsultantConfig(nil)
        consultantView.setContactFormPresentation(.hidden)
        consultantView.setInputBarHidden(false)
        consultantView.setCanSendMessages(false)
        consultantView.setCanLoadOlderMessages(false)
    }

}
