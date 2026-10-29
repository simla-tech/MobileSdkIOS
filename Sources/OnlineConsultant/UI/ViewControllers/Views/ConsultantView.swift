import UIKit

/// Root chat view that renders messages, contact forms, the agreement notice, and the input composer.
///
/// The view owns message list presentation, incremental collection updates, scroll anchoring, keyboard
/// handling, attachment preview loading state, and UI callbacks forwarded to `OnlineConsultantViewController`.
 package final class ConsultantView: UIView {

    private static let historyPreloadViewportMultiplier: CGFloat = 3
    private static let historyLoadingBufferViewportMultiplier: CGFloat = 4

    private lazy var messagesContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var agreementView: AgreementView = {
        let view = AgreementView()
        view.onTap = { [weak self] url in
            self?.onAgreementTap?(url)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var messagesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 2
        layout.minimumInteritemSpacing = 0
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .none
        collectionView.backgroundColor = .systemBackground
        collectionView.showsVerticalScrollIndicator = true
        collectionView.accessibilityIdentifier = "messagesCollectionView"
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            MessageCollectionViewCell.self,
            forCellWithReuseIdentifier: CellReuseIdentifier.message.rawValue
        )
        collectionView.panGestureRecognizer.addTarget(
            self,
            action: #selector(messagesCollectionViewPanGestureDidChange)
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var inputBarView: InputBar = {
        let view = InputBar()
        view.onSend = { [weak self] text in
            self?.sendMessage(text)
        }
        view.onOpenAttachmentMenu = { [weak self] sourceView in
            self?.onOpenAttachmentMenu?(sourceView)
        }
        view.onRemoveInputAttachment = { [weak self] id in
            self?.onRemoveInputAttachment?(id)
        }
        view.onRetryInputAttachment = { [weak self] id in
            self?.onRetryInputAttachment?(id)
        }
        view.onIntrinsicContentSizeChange = { [weak self] in
            self?.inputBarIntrinsicContentSizeDidChange()
        }
        view.addGestureRecognizer(inputBarKeyboardDismissPanGestureRecognizer)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var footerBrandingView: FooterBrandingView = {
        let view = FooterBrandingView()
        view.isHidden = true
        view.onTap = { [weak self] url in
            self?.onBrandingFooterTap?(url)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contactFormView: ContactFormView = {
        let view = ContactFormView()
        view.isHidden = true
        view.onSubmit = { [weak self] data in
            self?.onContactFormSubmit?(data)
        }
        view.onPersonalDataLinkTap = { [weak self] url in
            self?.onAgreementTap?(url)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var stateView: ConsultantStateView = {
        let view = ConsultantStateView()
        view.isHidden = true
        return view
    }()

    private lazy var inputBarKeyboardDismissPanGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(inputBarKeyboardDismissPanGestureDidChange)
        )
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private var realMessages: [ConsultantMessage] = []
    private var messages: [ConsultantMessage] = []
    private var messageItemIDs: [MessageItemID] = []
    private var contactFormMessage: ConsultantMessage?
    private var fullscreenContactForm: ContactForm?
    private var isContactFormSubmitting = false
    private var canSendMessages = false
    private var inputAttachments: [InputAttachment] = []
    private var loadingFilePreviewIDs: Set<String> = []
    private var loadingImagePreviewIDs: Set<String> = []
    private var isLoadingOlderMessages = false
    private var canLoadOlderMessages = true
    private var historyLoadingSpacerHeight: CGFloat = 0
    private var shouldKeepMessagesPinnedToBottom = false
    private var isScrollToBottomAfterLayoutScheduled = false
    private var isVisibleReadCheckScheduled = false
    private var consultantConfig: ConsultantConfig?
    private var theme = ConsultantTheme.defaultTheme
    private var managerIdentity = ManagerIdentity(config: nil)
    private var inputBarBottomConstraint: NSLayoutConstraint?
    private var messagesBottomToInputBarConstraint: NSLayoutConstraint?
    private var messagesBottomToFooterConstraint: NSLayoutConstraint?
    private var footerBrandingHeightConstraint: NSLayoutConstraint?
    private var isInputBarHidden = false
    private var isObservingKeyboard = false
    private var lastVisibleReadMessageID: String?

    /// Called when the visitor submits contact form data from the fullscreen form or a message bubble.
     package var onContactFormSubmit: ((ContactFormSubmitData) -> Void)?

    package var onSendMessage: ((String) -> Void)?
    package var onRetryMessage: ((String) -> Void)?
    package var onOpenAttachmentMenu: ((UIView) -> Void)?
    package var onRemoveInputAttachment: ((UUID) -> Void)?
    package var onRetryInputAttachment: ((UUID) -> Void)?
    package var onQuoteTap: ((String) -> Void)?
    package var onLoadOlderMessages: (() -> Void)?
    package var onImagePreview: (([ImagePreviewItem], Int) -> Void)?
    package var onFilePreview: (([FilePreviewItem], Int) -> Void)?
    package var onMessageLinkTap: ((URL) -> Void)?
    package var onAgreementTap: ((URL) -> Void)?
    package var onBrandingFooterTap: ((URL) -> Void)?
    package var onVisibleIncomingMessagesRead: ((String) -> Bool)?
    package var onStateRetry: (() -> Void)? {
        get {
            stateView.onRetry
        }
        set {
            stateView.onRetry = newValue
        }
    }

    /// Creates the root chat view programmatically.
     package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    /// Creates the root chat view from a storyboard or nib.
     package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        quoteScrollDisplayLink?.invalidate()
        unregisterForKeyboardNotifications()
    }

    /// Starts keyboard observation when the view enters a window and stops it when the view is removed.
     package override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            stopQuoteScrollAnimation()
            unregisterForKeyboardNotifications()
            inputBarBottomConstraint?.constant = 0
        } else {
            registerForKeyboardNotifications()
            scheduleVisibleIncomingMessagesReadCheck()
        }
    }

    /// Updates message list insets and keeps the list pinned to the bottom after layout changes.
     package override func layoutSubviews() {
        super.layoutSubviews()
        updateMessagesContentInset()
        pinMessagesToBottomIfNeeded()
        scheduleScrollToBottomAfterLayoutIfNeeded()
        markVisibleIncomingMessagesReadIfNeeded()
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
        applyTheme()
    }

    private func setupSubviews() {
        addSubview(agreementView)
        addSubview(messagesContainerView)
        addSubview(inputBarView)
        addSubview(footerBrandingView)
        addSubview(contactFormView)
        addSubview(stateView)
        messagesContainerView.addSubview(messagesCollectionView)
        updateSendMessageControls()
    }

    private func setupConstraints() {
        let inputBarBottomConstraint = footerBrandingView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        let footerBrandingHeightConstraint = footerBrandingView.heightAnchor.constraint(equalToConstant: 0)
        let messagesBottomToInputBarConstraint = messagesContainerView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor)
        let messagesBottomToFooterConstraint = messagesContainerView.bottomAnchor.constraint(equalTo: footerBrandingView.topAnchor)
        self.inputBarBottomConstraint = inputBarBottomConstraint
        self.footerBrandingHeightConstraint = footerBrandingHeightConstraint
        self.messagesBottomToInputBarConstraint = messagesBottomToInputBarConstraint
        self.messagesBottomToFooterConstraint = messagesBottomToFooterConstraint

        NSLayoutConstraint.activate([
            agreementView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            agreementView.leadingAnchor.constraint(equalTo: leadingAnchor),
            agreementView.trailingAnchor.constraint(equalTo: trailingAnchor),

            messagesContainerView.topAnchor.constraint(equalTo: agreementView.bottomAnchor),
            messagesContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            messagesContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            messagesBottomToInputBarConstraint,

            messagesCollectionView.topAnchor.constraint(equalTo: messagesContainerView.topAnchor),
            messagesCollectionView.leadingAnchor.constraint(equalTo: messagesContainerView.leadingAnchor),
            messagesCollectionView.trailingAnchor.constraint(equalTo: messagesContainerView.trailingAnchor),
            messagesCollectionView.bottomAnchor.constraint(equalTo: messagesContainerView.bottomAnchor),

            inputBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBarView.bottomAnchor.constraint(equalTo: footerBrandingView.topAnchor),

            footerBrandingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerBrandingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBarBottomConstraint,
            footerBrandingHeightConstraint,

            contactFormView.topAnchor.constraint(equalTo: agreementView.bottomAnchor),
            contactFormView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contactFormView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contactFormView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stateView.topAnchor.constraint(equalTo: topAnchor),
            stateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stateView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Shows, hides, or embeds the configured contact form according to the current presentation mode.
     package func setContactFormPresentation(_ presentation: ContactFormPresentation) {
        contactFormView.setSubmitting(false)
        isContactFormSubmitting = false

        switch presentation {
        case .hidden, .waitingForFirstMessage:
            contactFormView.isHidden = true
            fullscreenContactForm = nil
            contactFormMessage = nil
        case .visible(let form):
            if form.display == .atBeginningDialogue {
                fullscreenContactForm = form
                contactFormView.setPersonalDataLink(consultantConfig?.personalDataLink)
                contactFormView.configure(form: form)
                contactFormView.isHidden = false
                bringSubviewToFront(contactFormView)
                contactFormMessage = nil
            } else {
                contactFormView.isHidden = true
                fullscreenContactForm = nil
                contactFormMessage = Self.makeContactFormMessage(form)
            }
        }

        updateAgreementView()
        applyDisplayedMessages()
    }

    /// Updates contact form submitting state in both fullscreen and message-bubble presentations.
     package func setContactFormSubmitting(_ isSubmitting: Bool) {
        isContactFormSubmitting = isSubmitting
        if isSubmitting {
            contactFormView.setSubmitError(nil)
        }
        contactFormView.setSubmitting(isSubmitting)
        messagesCollectionView.visibleCells
            .compactMap { $0 as? MessageCollectionViewCell }
            .forEach { $0.setContactFormSubmitting(isSubmitting) }
    }

    /// Displays or clears the contact form submit error shown by the fullscreen form.
     package func setContactFormSubmitError(_ message: String?) {
        contactFormView.setSubmitError(message)
    }

    package func setCanSendMessages(_ canSend: Bool) {
        guard canSendMessages != canSend else {
            return
        }

        canSendMessages = canSend
        updateSendMessageControls()
    }

    package func setInputBarHidden(_ isHidden: Bool) {
        guard isInputBarHidden != isHidden else {
            return
        }

        isInputBarHidden = isHidden
        inputBarView.isHidden = isHidden
        inputBarView.endEditing(true)
        messagesBottomToInputBarConstraint?.isActive = !isHidden
        messagesBottomToFooterConstraint?.isActive = isHidden

        setNeedsLayout()
        inputBarIntrinsicContentSizeDidChange()
    }

    package func clearMessageInput() {
        inputBarView.clearText()
    }

    package func setStateViewMode(_ mode: ConsultantStateView.Mode) {
        stateView.setMode(mode)
        if mode != .hidden {
            bringSubviewToFront(stateView)
        }
    }

    package func setInputAttachments(_ attachments: [InputAttachment]) {
        inputAttachments = attachments
        inputBarView.setInputAttachments(attachments)
    }

    package func setLoadingFilePreviewIDs(_ fileIDs: Set<String>) {
        guard loadingFilePreviewIDs != fileIDs else {
            return
        }

        loadingFilePreviewIDs = fileIDs
        reconfigureVisibleMessageCells()
    }

    package func setLoadingImagePreviewIDs(_ fileIDs: Set<String>) {
        guard loadingImagePreviewIDs != fileIDs else {
            return
        }

        loadingImagePreviewIDs = fileIDs
        reconfigureVisibleMessageCells()
    }

    package func setLoadingOlderMessages(_ isLoading: Bool) {
        guard isLoadingOlderMessages != isLoading else {
            return
        }

        isLoadingOlderMessages = isLoading
    }

    package func setCanLoadOlderMessages(_ canLoad: Bool) {
        canLoadOlderMessages = canLoad
    }

    /// Applies backend-provided consultant configuration to theme, manager identity, agreement, and messages.
     package func setConsultantConfig(_ config: ConsultantConfig?) {
         guard consultantConfig != config else {
             return
         }

         consultantConfig = config
         theme = ConsultantTheme(config: config)
         managerIdentity = ManagerIdentity(config: config)
         applyTheme()
         inputBarView.setTheme(theme)
         contactFormView.setTheme(theme)
         stateView.setTheme(theme)
         contactFormView.setPersonalDataLink(consultantConfig?.personalDataLink)
         messagesCollectionView.reloadData()
         updateAgreementView()
    }

    /// Replaces the backend message list and refreshes the displayed chat timeline.
     package func setMessages(_ messages: [ConsultantMessage]) {
        realMessages = messages
        lastVisibleReadMessageID = nil
        updateAgreementView()
        applyDisplayedMessages()
    }

    private var pendingQuoteMessageID: String?
    private var scrollingToQuoteMessageID: String?
    private var quoteScrollDisplayLink: CADisplayLink?
    private var quoteScrollStartTime: CFTimeInterval = 0
    private var quoteScrollStartY: CGFloat = 0
    private var quoteScrollTargetY: CGFloat = 0
    private var messageListUpdatesInFlight = 0

    /// Waits for collection updates before scrolling and highlighting the requested message.
    @discardableResult
    package func revealMessage(id: String) -> Bool {
        guard messages.contains(where: { $0.id?.value == id && $0.status != .deleted }) else { return false }
        stopQuoteScrollAnimation()
        shouldKeepMessagesPinnedToBottom = false
        pendingQuoteMessageID = id
        revealPendingQuoteIfNeeded()
        return true
    }

    private func revealPendingQuoteIfNeeded() {
        guard messageListUpdatesInFlight == 0, let id = pendingQuoteMessageID,
              let index = messages.firstIndex(where: { $0.id?.value == id }) else { return }
        pendingQuoteMessageID = nil
        shouldKeepMessagesPinnedToBottom = false
        messagesCollectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: index, section: 0)
        guard let attributes = messagesCollectionView.layoutAttributesForItem(at: indexPath) else { return }
        let insets = messagesCollectionView.adjustedContentInset
        let visibleHeight = messagesCollectionView.bounds.height - insets.top - insets.bottom
        let targetY = clampedContentOffsetY(attributes.frame.midY - insets.top - visibleHeight / 2)
        scrollingToQuoteMessageID = id
        if abs(messagesCollectionView.contentOffset.y - targetY) < 1 || UIAccessibility.isReduceMotionEnabled {
            messagesCollectionView.setContentOffset(CGPoint(x: messagesCollectionView.contentOffset.x, y: targetY), animated: false)
            finishQuoteNavigation()
        } else {
            quoteScrollStartY = messagesCollectionView.contentOffset.y
            quoteScrollTargetY = targetY
            quoteScrollStartTime = CACurrentMediaTime()
            let target = QuoteScrollAnimationTarget(view: self)
            let link = CADisplayLink(target: target, selector: #selector(QuoteScrollAnimationTarget.tick(_:)))
            quoteScrollDisplayLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    package func advanceQuoteScrollAnimation(_ timestamp: CFTimeInterval) {
        let progress = min(1, max(0, (timestamp - quoteScrollStartTime) / 0.3))
        let easedProgress = CGFloat(1 - pow(1 - progress, 3))
        let y = quoteScrollStartY + (quoteScrollTargetY - quoteScrollStartY) * easedProgress
        messagesCollectionView.setContentOffset(CGPoint(x: messagesCollectionView.contentOffset.x, y: y), animated: false)
        if progress >= 1 {
            quoteScrollDisplayLink?.invalidate()
            quoteScrollDisplayLink = nil
            finishQuoteNavigation()
        }
    }

    private func stopQuoteScrollAnimation() {
        quoteScrollDisplayLink?.invalidate()
        quoteScrollDisplayLink = nil
        scrollingToQuoteMessageID = nil
    }

    private func finishQuoteNavigation() {
        guard let id = scrollingToQuoteMessageID,
              let index = messages.firstIndex(where: { $0.id?.value == id }) else { return }
        scrollingToQuoteMessageID = nil
        messagesCollectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: index, section: 0)
        (messagesCollectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell)?.highlightQuotedMessage()
        scheduleVisibleIncomingMessagesReadCheck()
    }

    private func applyDisplayedMessages() {
        let oldMessages = self.messages
        let oldItemIDs = messageItemIDs
        let newMessages = realMessages.sortedForChatDisplay()
            + [contactFormMessage].compactMap { $0 }
        let newItemIDs = Self.makeItemIDs(for: newMessages)
        let shouldScrollToBottom = scrollingToQuoteMessageID == nil
            && (oldMessages.isEmpty || shouldKeepMessagesPinnedToBottom || isScrolledNearBottom())

        guard messagesCollectionView.bounds.width > 0,
              messagesCollectionView.bounds.height > 0 else {
            messages = newMessages
            messageItemIDs = newItemIDs
            updateMessagesBottomPinning(shouldScrollToBottom)
            messagesCollectionView.reloadData()
            setNeedsLayout()
            return
        }

        if !shouldScrollToBottom,
           !oldMessages.isEmpty,
           applyPrependedMessages(
               oldMessages: oldMessages,
               oldItemIDs: oldItemIDs,
               newMessages: newMessages,
               newItemIDs: newItemIDs
           ) {
            return
        }

        let update = makeMessageListUpdate(
            oldMessages: oldMessages,
            oldItemIDs: oldItemIDs,
            newMessages: newMessages,
            newItemIDs: newItemIDs
        )

        self.messages = newMessages
        messageItemIDs = newItemIDs

        apply(update: update, shouldScrollToBottom: shouldScrollToBottom)
    }

    private func applyPrependedMessages(
        oldMessages: [ConsultantMessage],
        oldItemIDs: [MessageItemID],
        newMessages: [ConsultantMessage],
        newItemIDs: [MessageItemID]
    ) -> Bool {
        guard
            newItemIDs.count > oldItemIDs.count,
            Array(newItemIDs.suffix(oldItemIDs.count)) == oldItemIDs
        else {
            return false
        }

        let historyLoadingBufferHeight = messagesCollectionView.bounds.height
            * Self.historyLoadingBufferViewportMultiplier
        messagesCollectionView.layoutIfNeeded()
        let oldContentHeight = messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
        let oldContentOffsetY = messagesCollectionView.contentOffset.y
        let insertedCount = newItemIDs.count - oldItemIDs.count
        let insertedIndexPaths = (0..<insertedCount).map { IndexPath(item: $0, section: 0) }

        var reloadedIndexPaths = Self.reloadIndexPaths(
            oldMessages: oldMessages,
            oldItemIDs: oldItemIDs,
            newMessages: newMessages,
            newItemIDs: newItemIDs
        )
        .filter { $0.item >= insertedCount }

        // The first old cell can change grouping after prepending older messages.
        if oldItemIDs.indices.contains(0) {
            let firstOldIndexPath = IndexPath(item: insertedCount, section: 0)
            if !reloadedIndexPaths.contains(firstOldIndexPath) {
                reloadedIndexPaths.append(firstOldIndexPath)
            }
        }

        messages = newMessages
        messageItemIDs = newItemIDs

        messageListUpdatesInFlight += 1
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setHistoryLoadingSpacerHeight(historyLoadingBufferHeight)
            messagesCollectionView.performBatchUpdates {
                messagesCollectionView.insertItems(at: insertedIndexPaths)
                if !reloadedIndexPaths.isEmpty {
                    messagesCollectionView.reloadItems(at: reloadedIndexPaths)
                }
            } completion: { [weak self] _ in
                guard let self else { return }

                self.messagesCollectionView.layoutIfNeeded()
                let newContentHeight = self.messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
                let contentHeightIncrease = max(0, newContentHeight - oldContentHeight)
                self.setHistoryLoadingSpacerHeight(0)
                self.messagesCollectionView.setContentOffset(
                    CGPoint(
                        x: self.messagesCollectionView.contentOffset.x,
                        y: self.clampedContentOffsetY(oldContentOffsetY + contentHeightIncrease)
                    ),
                    animated: false
                )
                self.messagesCollectionView.layoutIfNeeded()
                self.messageListUpdatesInFlight -= 1
                self.revealPendingQuoteIfNeeded()
            }
            CATransaction.commit()
        }

        return true
    }

    private func makeMessageListUpdate(
        oldMessages: [ConsultantMessage],
        oldItemIDs: [MessageItemID],
        newMessages: [ConsultantMessage],
        newItemIDs: [MessageItemID]
    ) -> MessageListUpdate {
        guard !oldMessages.isEmpty else {
            return .reloadData
        }

        if newItemIDs.count > oldItemIDs.count,
           Array(newItemIDs.prefix(oldItemIDs.count)) == oldItemIDs {
            let insertedRange = oldItemIDs.count..<newItemIDs.count
            let insertedIndexPaths = insertedRange.map { IndexPath(item: $0, section: 0) }
            let reloadedIndexPaths = Self.reloadIndexPaths(
                oldMessages: oldMessages,
                oldItemIDs: oldItemIDs,
                newMessages: newMessages,
                newItemIDs: newItemIDs
            )
            .filter { !insertedRange.contains($0.item) }

            return .insertAndReload(inserted: insertedIndexPaths, reloaded: reloadedIndexPaths)
        }

        if oldItemIDs == newItemIDs {
            if let statusIndexPaths = Self.deliveryStatusOnlyIndexPaths(
                oldMessages: oldMessages,
                newMessages: newMessages
            ) {
                return .updateDeliveryStatuses(statusIndexPaths)
            }

            let reloadedIndexPaths = Self.reloadIndexPaths(
                oldMessages: oldMessages,
                oldItemIDs: oldItemIDs,
                newMessages: newMessages,
                newItemIDs: newItemIDs
            )

            return .reloadItems(reloadedIndexPaths)
        }

        if let reloadedIndexPaths = Self.samePositionReloadIndexPaths(
            oldMessages: oldMessages,
            oldItemIDs: oldItemIDs,
            newMessages: newMessages,
            newItemIDs: newItemIDs
        ) {
            return .reconfigureItems(reloadedIndexPaths)
        }

        return .reloadData
    }

    private func apply(update: MessageListUpdate, shouldScrollToBottom: Bool) {
        messageListUpdatesInFlight += 1
        updateMessagesBottomPinning(shouldScrollToBottom)
        let completion = { [weak self] in
            guard let self else { return }
            self.messagesCollectionView.layoutIfNeeded()
            self.updateMessagesContentInset()
            self.scrollToBottomIfPinned()
            self.scheduleScrollToBottomAfterLayoutIfNeeded()
            self.markVisibleIncomingMessagesReadIfNeeded()
            self.scheduleVisibleIncomingMessagesReadCheck()
            self.messageListUpdatesInFlight -= 1
            self.revealPendingQuoteIfNeeded()
        }

        switch update {
        case .reloadData:
            UIView.performWithoutAnimation {
                messagesCollectionView.reloadData()
                completion()
            }
        case let .reloadItems(reloadedIndexPaths):
            guard !reloadedIndexPaths.isEmpty else {
                completion()
                return
            }

            UIView.performWithoutAnimation {
                messagesCollectionView.reloadItems(at: reloadedIndexPaths)
                completion()
            }
        case let .reconfigureItems(reconfiguredIndexPaths):
            guard !reconfiguredIndexPaths.isEmpty else {
                completion()
                return
            }

            UIView.performWithoutAnimation {
                reconfigureVisibleMessageCells(at: reconfiguredIndexPaths)
                completion()
            }
        case let .updateDeliveryStatuses(indexPaths):
            guard !indexPaths.isEmpty else {
                completion()
                return
            }

            UIView.performWithoutAnimation {
                updateVisibleDeliveryStatuses(at: indexPaths)
                completion()
            }
        case let .insertAndReload(insertedIndexPaths, reloadedIndexPaths):
            guard !insertedIndexPaths.isEmpty || !reloadedIndexPaths.isEmpty else {
                completion()
                return
            }

            messagesCollectionView.performBatchUpdates {
                if !insertedIndexPaths.isEmpty {
                    messagesCollectionView.insertItems(at: insertedIndexPaths)
                }
                if !reloadedIndexPaths.isEmpty {
                    messagesCollectionView.reloadItems(at: reloadedIndexPaths)
                }
            } completion: { _ in
                completion()
            }
        }
    }

    private func updateVisibleDeliveryStatuses(at indexPaths: [IndexPath]) {
        indexPaths.forEach { indexPath in
            guard
                messages.indices.contains(indexPath.item),
                let cell = messagesCollectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell
            else {
                return
            }

            cell.updateDeliveryStatus(
                message: messages[indexPath.item],
                theme: theme
            )
        }
    }

    private func reconfigureVisibleMessageCells() {
        reconfigureVisibleMessageCells(at: messagesCollectionView.indexPathsForVisibleItems)
    }

    private func reconfigureVisibleMessageCells(at indexPaths: [IndexPath]) {
        indexPaths.forEach { indexPath in
            guard
                messages.indices.contains(indexPath.item),
                let cell = messagesCollectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell
            else {
                return
            }

            configure(cell, at: indexPath)
        }
    }

    private func configure(_ cell: MessageCollectionViewCell, at indexPath: IndexPath) {
        let message = messages[indexPath.item]
        let context = Self.presentationContext(messages: messages, index: indexPath.item)

        cell.configure(
            message: message,
            dateSeparatorText: context.dateSeparator.map { MessageDateSeparator.text(for: $0) },
            showsAvatar: context.showsAvatar,
            showsAuthor: context.showsAuthor,
            roundsAllCorners: context.roundsAllCorners,
            theme: theme,
            managerIdentity: managerIdentity,
            imageWorkers: consultantConfig?.imageWorkers ?? [],
            loadingFilePreviewIDs: loadingFilePreviewIDs,
            loadingImagePreviewIDs: loadingImagePreviewIDs,
            isContactFormSubmitting: isContactFormSubmitting,
            onImagePreview: { [weak self] items, index in
                self?.onImagePreview?(items, index)
            },
            onFilePreview: { [weak self] items, index in
                self?.onFilePreview?(items, index)
            },
            onContactFormSubmit: { [weak self] data in
                self?.onContactFormSubmit?(data)
            },
            onPersonalDataLinkTap: { [weak self] url in
                self?.onAgreementTap?(url)
            },
            personalDataLink: consultantConfig?.personalDataLink,
            onLinkTap: { [weak self] url in
                self?.onMessageLinkTap?(url)
            },
            onQuoteTap: { [weak self] id in self?.onQuoteTap?(id) }
        )
    }

    private func sendMessage(_ text: String) {
        let hasSendableContent = !text.isEmpty || !inputAttachments.isEmpty
        let canSendInputAttachments = inputAttachments.allSatisfy(\.canSend)

        guard canSendMessages, canSendInputAttachments, hasSendableContent else {
            return
        }

        onSendMessage?(text)
    }

    private func updateSendMessageControls() {
        inputBarView.setCanSendMessages(canSendMessages)
    }

    private func inputBarIntrinsicContentSizeDidChange() {
        // The composer can notify us during setup, before UIKit sizes the root view.
        setNeedsLayout()
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }

        updateMessagesBottomPinning(isScrolledNearBottom())

        UIView.animate(withDuration: 0.2) {
            self.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self else { return }

            self.updateMessagesContentInset()
            self.scrollToBottomIfPinned()
            self.scheduleScrollToBottomAfterLayoutIfNeeded()
        }
    }

    private func applyTheme() {
        backgroundColor = theme.screenBackgroundColor
        messagesContainerView.backgroundColor = theme.screenBackgroundColor
        messagesCollectionView.backgroundColor = theme.screenBackgroundColor
        footerBrandingView.configure(domainConfig: consultantConfig?.domainConfig, theme: theme)
        updateFooterBrandingVisibility()
        updateAgreementView()
    }

    private func updateAgreementView() {
        let contactFormWithPersonalData = fullscreenContactForm?.fields[.personalData] != nil
            || contactFormMessage?.contactForm?.fields[.personalData] != nil
            || realMessages.contains { $0.contactForm?.fields[.personalData] != nil }
        agreementView.configure(
            theme: theme,
            link: consultantConfig?.personalDataConsent == true && !contactFormWithPersonalData
                ? consultantConfig?.personalDataLink
                : nil
        )
    }

    private func updateFooterBrandingVisibility() {
        let shouldShowFooterBranding = consultantConfig?.domainConfig?.footer == true
        footerBrandingView.isHidden = !shouldShowFooterBranding
        footerBrandingHeightConstraint?.constant = shouldShowFooterBranding ? 31 : 0
        setNeedsLayout()
    }

    private func registerForKeyboardNotifications() {
        guard !isObservingKeyboard else { return }
        isObservingKeyboard = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func unregisterForKeyboardNotifications() {
        guard isObservingKeyboard else { return }
        isObservingKeyboard = false

        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            window != nil,
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        // Hidden keyboards can report an empty frame while the context menu transforms the window.
        // There is no overlap to convert in that case.
        guard !endFrame.isEmpty, !endFrame.isNull, !endFrame.isInfinite else {
            updateInputBarBottomOffset(0, notification: notification)
            return
        }

        let keyboardFrame = convert(endFrame, from: nil)
        let keyboardOverlap = max(0, bounds.maxY - keyboardFrame.minY)
        let bottomOffset = max(0, keyboardOverlap - safeAreaInsets.bottom)
        updateInputBarBottomOffset(bottomOffset, notification: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        updateInputBarBottomOffset(0, notification: notification)
    }

    private func updateInputBarBottomOffset(_ offset: CGFloat, notification: Notification) {
        updateMessagesBottomPinning(isScrolledNearBottom())
        inputBarBottomConstraint?.constant = -offset
        animateKeyboardLayout(notification: notification) {
            self.layoutIfNeeded()
        } completion: { [weak self] in
            guard let self else { return }

            self.updateMessagesContentInset()
            self.scrollToBottomIfPinned()
            self.scheduleScrollToBottomAfterLayoutIfNeeded()
        }
    }

    private func animateKeyboardLayout(
        notification: Notification,
        animations: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 0
        let options = UIView.AnimationOptions(rawValue: UInt(curve << 16))

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: animations,
            completion: { _ in completion?() }
        )
    }

    private func isScrolledNearBottom() -> Bool {
        let topOffset = -messagesCollectionView.adjustedContentInset.top
        let bottomOffset = max(
            topOffset,
            messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
            - messagesCollectionView.bounds.height
            + messagesCollectionView.adjustedContentInset.bottom
        )
        return messagesCollectionView.contentOffset.y >= bottomOffset - 80
    }

    private func updateMessagesContentInset() {
        let contentHeight = messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
        let topInset = max(0, messagesCollectionView.bounds.height - contentHeight)
            + historyLoadingSpacerHeight
        guard abs(messagesCollectionView.contentInset.top - topInset) > 0.5 else {
            return
        }

        messagesCollectionView.contentInset.top = topInset
        messagesCollectionView.verticalScrollIndicatorInsets.top = topInset
    }

    private func setHistoryLoadingSpacerHeight(_ height: CGFloat) {
        guard abs(historyLoadingSpacerHeight - height) > 0.5 else {
            return
        }

        historyLoadingSpacerHeight = height

        UIView.performWithoutAnimation {
            updateMessagesContentInset()
            messagesCollectionView.layoutIfNeeded()
        }
    }

    private func updateMessagesBottomPinning(_ shouldPin: Bool) {
        // Preserve pinning across overlapping updates; a manual scroll cancels it.
        shouldKeepMessagesPinnedToBottom = (shouldKeepMessagesPinnedToBottom || shouldPin)
            && !messagesCollectionView.isDragging
            && !messagesCollectionView.isDecelerating
    }

    private func scheduleScrollToBottomAfterLayoutIfNeeded() {
        guard
            shouldKeepMessagesPinnedToBottom,
            !isScrollToBottomAfterLayoutScheduled
        else {
            return
        }

        isScrollToBottomAfterLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isScrollToBottomAfterLayoutScheduled = false
            self.scrollToBottomIfPinned()
            self.scheduleVisibleIncomingMessagesReadCheck()
        }
    }

    package func scheduleVisibleIncomingMessagesReadCheck() {
        guard !isVisibleReadCheckScheduled else {
            return
        }

        isVisibleReadCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isVisibleReadCheckScheduled = false
            guard self.window != nil,
                  self.messagesCollectionView.bounds.width > 0,
                  self.messagesCollectionView.bounds.height > 0 else { return }
            self.messagesCollectionView.layoutIfNeeded()
            self.markVisibleIncomingMessagesReadIfNeeded()
        }
    }

    private func scrollToBottomIfPinned() {
        guard
            shouldKeepMessagesPinnedToBottom,
            !messages.isEmpty,
            messagesCollectionView.bounds.width > 0,
            messagesCollectionView.bounds.height > 0
        else {
            return
        }

        scrollToBottom()
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else {
            return
        }

        messagesCollectionView.layoutIfNeeded()
        updateMessagesContentInset()
        messagesCollectionView.collectionViewLayout.invalidateLayout()
        messagesCollectionView.layoutIfNeeded()

        UIView.performWithoutAnimation {
            setMessagesContentOffsetToBottom()
            messagesCollectionView.layoutIfNeeded()
        }
    }

    private func pinMessagesToBottomIfNeeded() {
        guard
            shouldKeepMessagesPinnedToBottom,
            !messages.isEmpty,
            messagesCollectionView.bounds.width > 0,
            messagesCollectionView.bounds.height > 0
        else {
            return
        }

        UIView.performWithoutAnimation {
            setMessagesContentOffsetToBottom()
        }
    }

    private func setMessagesContentOffsetToBottom() {
        let bottomOffsetY = max(
            -messagesCollectionView.adjustedContentInset.top,
            messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
                - messagesCollectionView.bounds.height
                + messagesCollectionView.adjustedContentInset.bottom
        )
        let contentOffset = CGPoint(x: messagesCollectionView.contentOffset.x, y: bottomOffsetY)
        messagesCollectionView.setContentOffset(contentOffset, animated: false)
    }

    private func requestOlderMessagesIfNeeded(_ scrollView: UIScrollView) {
        guard
            !isLoadingOlderMessages,
            canLoadOlderMessages,
            contactFormView.isHidden,
            !messages.isEmpty,
            scrollView.isDragging || scrollView.isDecelerating,
            let onLoadOlderMessages
        else {
            return
        }

        let topOffset = -scrollView.adjustedContentInset.top
        let preloadDistance = scrollView.bounds.height * Self.historyPreloadViewportMultiplier
        guard scrollView.contentOffset.y <= topOffset + preloadDistance else {
            return
        }

        setLoadingOlderMessages(true)
        onLoadOlderMessages()
    }

    package func markVisibleIncomingMessagesReadIfNeeded() {
        guard
            window != nil,
            let messageID = maximumVisibleUnreadIncomingMessageID()
        else {
            return
        }

        guard messageID != lastVisibleReadMessageID else {
            return
        }

        guard onVisibleIncomingMessagesRead?(messageID) == true else {
            return
        }

        lastVisibleReadMessageID = messageID
    }

    private func maximumVisibleUnreadIncomingMessageID() -> String? {
        visibleMessageIndexPaths()
            .compactMap { indexPath -> UInt64? in
                guard
                    messages.indices.contains(indexPath.item),
                    let id = messages[indexPath.item].unreadIncomingBackendMessageID
                else {
                    return nil
                }

                return UInt64(id)
            }
            .max()
            .map(String.init)
    }

    private func visibleMessageIndexPaths() -> Set<IndexPath> {
        var indexPaths = Set(messagesCollectionView.indexPathsForVisibleItems)

        guard messagesCollectionView.bounds.width > 0,
              messagesCollectionView.bounds.height > 0 else {
            return indexPaths
        }

        messagesCollectionView.layoutIfNeeded()
        let attributes = messagesCollectionView.collectionViewLayout.layoutAttributesForElements(
            in: messagesCollectionView.bounds
        ) ?? []
        indexPaths.formUnion(attributes.map(\.indexPath))

        return indexPaths
    }

    private func clampedContentOffsetY(_ offsetY: CGFloat) -> CGFloat {
        let minOffsetY = -messagesCollectionView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            messagesCollectionView.collectionViewLayout.collectionViewContentSize.height
                - messagesCollectionView.bounds.height
                + messagesCollectionView.adjustedContentInset.bottom
        )

        return min(max(offsetY, minOffsetY), maxOffsetY)
    }

    @objc private func inputBarKeyboardDismissPanGestureDidChange(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.state == .changed else {
            return
        }

        guard gestureRecognizer.translation(in: self).y > 6 else {
            return
        }

        endEditing(true)
    }

    @objc private func messagesCollectionViewPanGestureDidChange(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.state == .changed else {
            return
        }

        guard gestureRecognizer.translation(in: self).y > 6 else {
            return
        }

        let touchLocation = gestureRecognizer.location(in: self)
        guard inputBarView.frame.insetBy(dx: 0, dy: -4).contains(touchLocation) else {
            return
        }

        endEditing(true)
    }
}

private extension ConsultantView {

    private struct MessageItemID: Hashable {
        let base: String
        let occurrence: Int
    }

    private enum MessageListUpdate {
        case reloadData
        case reloadItems([IndexPath])
        case reconfigureItems([IndexPath])
        case updateDeliveryStatuses([IndexPath])
        case insertAndReload(inserted: [IndexPath], reloaded: [IndexPath])
    }

    private struct MessagePresentationContext: Equatable {
        let dateSeparator: Date?
        let showsAvatar: Bool
        let showsAuthor: Bool
        let roundsAllCorners: Bool
    }
}

private extension ConsultantView {

    private static func makeItemIDs(for messages: [ConsultantMessage]) -> [MessageItemID] {
        var occurrences: [String: Int] = [:]

        return messages.enumerated().map { index, message in
            let base = itemIDBase(for: message, index: index)
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return MessageItemID(base: base, occurrence: occurrence)
        }
    }

    private static func itemIDBase(for message: ConsultantMessage, index: Int) -> String {
        if let id = message.id?.value, !id.isEmpty {
            return "backend:\(id)"
        }

        return [
            "local",
            String(index),
            message.time ?? "",
            message.updatedAt ?? "",
            message.messageType?.rawValue ?? "",
            message.content ?? ""
        ].joined(separator: ":")
    }

    private static func makeContactFormMessage(_ form: ContactForm) -> ConsultantMessage {
        ConsultantMessage(
            id: FlexibleID("_contact_form"),
            content: form.text,
            time: nil,
            user: MessageUser(
                firstName: ConsultantLocalization.messageAuthorConsultant.localized
            ),
            fromMe: nil,
            messageType: .contactForm,
            status: .seen,
            contactForm: form
        )
    }

    private static func reloadIndexPaths(
        oldMessages: [ConsultantMessage],
        oldItemIDs: [MessageItemID],
        newMessages: [ConsultantMessage],
        newItemIDs: [MessageItemID]
    ) -> [IndexPath] {
        guard !oldMessages.isEmpty else {
            return []
        }

        var reloadItemIDs = Set<MessageItemID>()
        let oldIndexByID = Dictionary(uniqueKeysWithValues: oldItemIDs.enumerated().map { ($0.element, $0.offset) })
        let newIndexByID = Dictionary(uniqueKeysWithValues: newItemIDs.enumerated().map { ($0.element, $0.offset) })
        let oldItemIDSet = Set(oldItemIDs)

        for (newIndex, itemID) in newItemIDs.enumerated() {
            guard let oldIndex = oldIndexByID[itemID] else {
                insertReloadNeighbors(
                    around: newIndex,
                    itemIDs: newItemIDs,
                    oldItemIDSet: oldItemIDSet,
                    into: &reloadItemIDs
                )
                continue
            }

            if oldMessages[oldIndex] != newMessages[newIndex]
                || presentationContext(messages: oldMessages, index: oldIndex)
                    != presentationContext(messages: newMessages, index: newIndex) {
                reloadItemIDs.insert(itemID)
            }
        }

        for (oldIndex, itemID) in oldItemIDs.enumerated() where newIndexByID[itemID] == nil {
            insertReloadNeighbors(
                aroundDeletedOldIndex: oldIndex,
                newItemIDs: newItemIDs,
                oldItemIDSet: oldItemIDSet,
                into: &reloadItemIDs
            )
        }

        return newItemIDs
            .filter { reloadItemIDs.contains($0) }
            .compactMap { newIndexByID[$0] }
            .map { IndexPath(item: $0, section: 0) }
    }

    private static func deliveryStatusOnlyIndexPaths(
        oldMessages: [ConsultantMessage],
        newMessages: [ConsultantMessage]
    ) -> [IndexPath]? {
        guard oldMessages.count == newMessages.count else {
            return nil
        }

        var indexPaths: [IndexPath] = []

        for index in oldMessages.indices {
            guard oldMessages[index] != newMessages[index] else {
                continue
            }

            guard
                presentationContext(messages: oldMessages, index: index)
                    == presentationContext(messages: newMessages, index: index),
                isDeliveryStatusOnlyChange(
                    oldMessage: oldMessages[index],
                    newMessage: newMessages[index]
                )
            else {
                return nil
            }

            indexPaths.append(IndexPath(item: index, section: 0))
        }

        return indexPaths
    }

    private static func isDeliveryStatusOnlyChange(
        oldMessage: ConsultantMessage,
        newMessage: ConsultantMessage
    ) -> Bool {
        guard
            oldMessage.id == newMessage.id,
            oldMessage.fromMe == true,
            oldMessage.status != newMessage.status
        else {
            return false
        }

        return oldMessage.content == newMessage.content
            && oldMessage.product == newMessage.product
            && oldMessage.order == newMessage.order
            && oldMessage.items == newMessage.items
            && oldMessage.quoteContent == newMessage.quoteContent
            && oldMessage.quoteID == newMessage.quoteID
            && oldMessage.quotePreview == newMessage.quotePreview
            && oldMessage.time == newMessage.time
            && oldMessage.user == newMessage.user
            && oldMessage.fromMe == newMessage.fromMe
            && oldMessage.messageType == newMessage.messageType
            && oldMessage.contactForm == newMessage.contactForm
    }

    private static func samePositionReloadIndexPaths(
        oldMessages: [ConsultantMessage],
        oldItemIDs: [MessageItemID],
        newMessages: [ConsultantMessage],
        newItemIDs: [MessageItemID]
    ) -> [IndexPath]? {
        guard
            oldMessages.count == newMessages.count,
            oldItemIDs.count == newItemIDs.count
        else {
            return nil
        }

        var reloadedIndices = Set<Int>()

        for index in oldMessages.indices {
            let itemIDChanged = oldItemIDs[index] != newItemIDs[index]
            let contentChanged = oldMessages[index] != newMessages[index]
                || presentationContext(messages: oldMessages, index: index)
                    != presentationContext(messages: newMessages, index: index)

            if itemIDChanged {
                guard isLocalMessageReplacement(
                    oldMessage: oldMessages[index],
                    newMessage: newMessages[index]
                ) else {
                    return nil
                }

                reloadedIndices.insert(index)
            } else if contentChanged {
                reloadedIndices.insert(index)
            }
        }

        return reloadedIndices
            .sorted()
            .map { IndexPath(item: $0, section: 0) }
    }

    private static func isLocalMessageReplacement(
        oldMessage: ConsultantMessage,
        newMessage: ConsultantMessage
    ) -> Bool {
        guard
            oldMessage.id?.value.hasPrefix("_local_") == true,
            newMessage.id?.value.hasPrefix("_local_") != true,
            oldMessage.fromMe == true,
            newMessage.fromMe == true,
            oldMessage.messageType == newMessage.messageType,
            oldMessage.content == newMessage.content
        else {
            return false
        }

        return oldMessage.status == .sending
            || oldMessage.status == .sent
            || oldMessage.status == .failed
    }

    private static func insertReloadNeighbors(
        around index: Int,
        itemIDs: [MessageItemID],
        oldItemIDSet: Set<MessageItemID>,
        into reloadItemIDs: inout Set<MessageItemID>
    ) {
        [index - 1, index + 1]
            .filter { itemIDs.indices.contains($0) }
            .map { itemIDs[$0] }
            .filter { oldItemIDSet.contains($0) }
            .forEach { reloadItemIDs.insert($0) }
    }

    private static func insertReloadNeighbors(
        aroundDeletedOldIndex oldIndex: Int,
        newItemIDs: [MessageItemID],
        oldItemIDSet: Set<MessageItemID>,
        into reloadItemIDs: inout Set<MessageItemID>
    ) {
        [oldIndex - 1, oldIndex]
            .filter { newItemIDs.indices.contains($0) }
            .map { newItemIDs[$0] }
            .filter { oldItemIDSet.contains($0) }
            .forEach { reloadItemIDs.insert($0) }
    }

    private static func presentationContext(
        messages: [ConsultantMessage],
        index: Int
    ) -> MessagePresentationContext {
        MessagePresentationContext(
            dateSeparator: MessageDateSeparator.date(messages: messages, index: index),
            showsAvatar: MessageGrouping.showsAvatar(
                messages: messages,
                index: index
            ),
            showsAuthor: MessageGrouping.showsAuthor(
                messages: messages,
                index: index
            ),
            roundsAllCorners: MessageGrouping.roundsAllCorners(
                messages: messages,
                index: index
            )
        )
    }
}

extension ConsultantView: UICollectionViewDataSource {

    /// Returns the number of message items currently displayed in the chat timeline.
     package func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        messages.count
    }

    /// Dequeues and configures a message cell for the requested timeline item.
     package func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            messages.indices.contains(indexPath.item),
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CellReuseIdentifier.message.rawValue,
                for: indexPath
            ) as? MessageCollectionViewCell
        else {
            return UICollectionViewCell()
        }

        configure(cell, at: indexPath)
        return cell
    }
}

extension ConsultantView: UIGestureRecognizerDelegate {

    /// Allows the input-bar dismissal pan gesture to work together with collection view scrolling.
     package func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === inputBarKeyboardDismissPanGestureRecognizer
    }
}

extension ConsultantView: UICollectionViewDelegateFlowLayout {

    /// Offers copying and retrying failed outgoing messages, including attachment-only messages.
    package func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard messages.indices.contains(indexPath.item) else { return nil }
        let message = messages[indexPath.item]
        guard message.clipboardText != nil || message.canRetrySending else { return nil }

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = []
            if let text = message.clipboardText {
                actions.append(UIAction(
                    title: ConsultantLocalization.messageActionCopy.localized,
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in
                    UIPasteboard.general.string = text
                })
            }
            if message.canRetrySending, let id = message.id?.value {
                actions.append(UIAction(
                    title: ConsultantLocalization.messageActionRetry.localized,
                    image: UIImage(systemName: "arrow.clockwise"),
                    attributes: self.canSendMessages ? [] : .disabled
                ) { [weak self] _ in
                    self?.onRetryMessage?(id)
                })
            }
            return UIMenu(children: actions)
        }
    }

    package func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        contextMenuPreview(in: collectionView, configuration: configuration)
    }

    package func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        contextMenuPreview(in: collectionView, configuration: configuration)
    }

    private func contextMenuPreview(
        in collectionView: UICollectionView,
        configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard
            let indexPath = configuration.identifier as? IndexPath,
            let cell = collectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell
        else {
            return nil
        }
        return cell.contextMenuPreview()
    }

    package func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        shouldKeepMessagesPinnedToBottom = false
        pendingQuoteMessageID = nil
        stopQuoteScrollAnimation()
    }

    package func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finishQuoteNavigation()
    }

    /// Tracks scroll position and requests older messages when the visitor scrolls near the top.
     package func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating {
            shouldKeepMessagesPinnedToBottom = false
        }

        requestOlderMessagesIfNeeded(scrollView)
        markVisibleIncomingMessagesReadIfNeeded()
    }

    package func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            shouldKeepMessagesPinnedToBottom = isScrolledNearBottom()
        }
    }

    package func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        shouldKeepMessagesPinnedToBottom = isScrolledNearBottom()
    }

    /// Returns the measured size for a message cell at the current collection width.
     package func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = collectionView.bounds.width
        guard width > 0 else {
            return CGSize(width: 1, height: 52)
        }

        return CGSize(
            width: width,
            height: (MessageDateSeparator.date(messages: messages, index: indexPath.item) == nil
                ? 0 : MessageCollectionViewCell.dateSeparatorHeight) + MessageCollectionViewCell.preferredHeight(
                for: messages[indexPath.item],
                collectionWidth: width,
                showsAuthor: MessageGrouping.showsAuthor(
                    messages: messages,
                    index: indexPath.item
                )
            )
        )
    }
}

private extension ConsultantMessage {

    var unreadIncomingBackendMessageID: String? {
        guard
            fromMe == false,
            status != .seen,
            status != .deleted,
            !isIntroMessage,
            let id = id?.value,
            UInt64(id) != nil
        else {
            return nil
        }

        return id
    }
}

/// CADisplayLink retains its target; the weak view reference allows the chat to deallocate mid-scroll.
@MainActor
private final class QuoteScrollAnimationTarget: NSObject {
    weak var view: ConsultantView?

    init(view: ConsultantView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        view?.advanceQuoteScrollAnimation(link.timestamp)
    }
}
