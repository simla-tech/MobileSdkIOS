import UIKit

/// Displays one chat message by selecting and configuring the matching bubble view.
package final class MessageCollectionViewCell: UICollectionViewCell {

    package static let dateSeparatorHeight: CGFloat = 40

    private lazy var dateSeparatorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.isHidden = true
        label.accessibilityIdentifier = "messageDateSeparatorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var bubbleTopConstraint: NSLayoutConstraint?

    private lazy var avatarView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 18
        view.clipsToBounds = true
        view.accessibilityIdentifier = "messageAvatarView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        view.accessibilityIdentifier = "messageAvatarImageView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var botAvatarImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.botIcon.templateImage
        view.contentMode = .scaleAspectFit
        view.tintColor = .black
        view.isHidden = true
        view.accessibilityIdentifier = "messageBotAvatarImageView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularSmallFont
        label.textAlignment = .center
        label.accessibilityIdentifier = "messageAvatarLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bubbleContainerView: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "messageBubbleContainerView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textMessageBubbleView: TextMessageBubbleView = {
        let view = TextMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var imageMessageBubbleView: ImageMessageBubbleView = {
        let view = ImageMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fileMessageBubbleView: FileMessageBubbleView = {
        let view = FileMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var quoteMessageBubbleView: QuoteMessageBubbleView = {
        let view = QuoteMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var productMessageBubbleView: ProductMessageBubbleView = {
        let view = ProductMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var orderMessageBubbleView: OrderMessageBubbleView = {
        let view = OrderMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contactFormMessageBubbleView: ContactFormMessageBubbleView = {
        let view = ContactFormMessageBubbleView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var activeBubbleView: UIView?
    private var activeBubbleConstraints: [NSLayoutConstraint] = []
    private var avatarWidthConstraint: NSLayoutConstraint?
    private var bubbleIncomingLeadingConstraint: NSLayoutConstraint?
    private var bubbleIncomingNoAvatarLeadingConstraint: NSLayoutConstraint?
    private var bubbleOutgoingTrailingConstraint: NSLayoutConstraint?
    private var bubbleIncomingTrailingConstraint: NSLayoutConstraint?
    private var bubbleOutgoingLeadingConstraint: NSLayoutConstraint?
    private var bubbleCenteredXConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var currentMessage: ConsultantMessage?
    private var currentReservesAvatarSpace = false
    private var currentShowsAuthor = false
    private var currentAuthorNameOverride: String?
    private var currentTheme = ConsultantTheme.defaultTheme
    private var avatarImageLoadTask: ImageLoadTask?
    private var currentAvatarURL: URL?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private var quoteHighlightView: UIView?

    /// Limits context menu animations to the message bubble, excluding the avatar and row margins.
    package func contextMenuPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: bubbleContainerView, parameters: parameters)
    }

    /// Briefly highlights the full message row, including the avatar and surrounding space.
    package func highlightQuotedMessage() {
        quoteHighlightView?.removeFromSuperview()
        let overlay = UIView(frame: contentView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = currentTheme.brandColor.withAlphaComponent(0.2)
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityIdentifier = "quoteNavigationHighlightView"
        contentView.addSubview(overlay)
        quoteHighlightView = overlay
        UIView.animate(withDuration: 1.5, delay: 0.2, options: [.allowUserInteraction]) {
            overlay.alpha = 0
        } completion: { _ in overlay.removeFromSuperview() }
    }

    /// Resets all bubble views, avatar loading, cached message state, and width constraints before reuse.
    package override func prepareForReuse() {
        super.prepareForReuse()
        quoteHighlightView?.layer.removeAllAnimations()
        quoteHighlightView?.removeFromSuperview()
        quoteHighlightView = nil
        removeActiveBubble()
        textMessageBubbleView.prepareForReuse()
        imageMessageBubbleView.prepareForReuse()
        fileMessageBubbleView.prepareForReuse()
        quoteMessageBubbleView.prepareForReuse()
        productMessageBubbleView.prepareForReuse()
        orderMessageBubbleView.prepareForReuse()
        contactFormMessageBubbleView.prepareForReuse()
        avatarImageLoadTask?.cancel()
        avatarImageLoadTask = nil
        currentAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarImageView.contentMode = .scaleAspectFill
        botAvatarImageView.isHidden = true
        avatarLabel.text = nil
        avatarLabel.isHidden = false
        avatarView.isHidden = false
        textMessageBubbleView.isHidden = true
        imageMessageBubbleView.isHidden = true
        fileMessageBubbleView.isHidden = true
        quoteMessageBubbleView.isHidden = true
        productMessageBubbleView.isHidden = true
        orderMessageBubbleView.isHidden = true
        contactFormMessageBubbleView.isHidden = true
        dateSeparatorLabel.text = nil
        dateSeparatorLabel.isHidden = true
        bubbleTopConstraint?.constant = 4
        currentMessage = nil
        currentReservesAvatarSpace = false
        currentShowsAuthor = false
        currentAuthorNameOverride = nil
        currentTheme = .defaultTheme
        bubbleWidthConstraint?.constant = 1
    }

    package override func layoutSubviews() {
        super.layoutSubviews()

        if let currentMessage {
            updateBubbleWidth(
                for: currentMessage,
                reservesAvatarSpace: currentReservesAvatarSpace
            )
        }
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        contentView.backgroundColor = .clear

        contentView.addSubview(dateSeparatorLabel)
        contentView.addSubview(avatarView)
        contentView.addSubview(bubbleContainerView)

        avatarView.addSubview(avatarImageView)
        avatarView.addSubview(botAvatarImageView)
        avatarView.addSubview(avatarLabel)
    }

    private func setupConstraints() {
        bubbleTopConstraint = bubbleContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)
        avatarWidthConstraint = avatarView.widthAnchor.constraint(equalToConstant: 36)
        bubbleIncomingLeadingConstraint = bubbleContainerView.leadingAnchor.constraint(
            equalTo: avatarView.trailingAnchor,
            constant: 8
        )
        bubbleIncomingNoAvatarLeadingConstraint = bubbleContainerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 16
        )
        bubbleOutgoingTrailingConstraint = bubbleContainerView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -12
        )
        bubbleIncomingTrailingConstraint = bubbleContainerView.trailingAnchor.constraint(
            lessThanOrEqualTo: contentView.trailingAnchor,
            constant: -16
        )
        bubbleOutgoingLeadingConstraint = bubbleContainerView.leadingAnchor.constraint(
            greaterThanOrEqualTo: contentView.leadingAnchor,
            constant: 16
        )
        bubbleCenteredXConstraint = bubbleContainerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        bubbleWidthConstraint = bubbleContainerView.widthAnchor.constraint(equalToConstant: 1)
        let bubbleBottomConstraint = bubbleContainerView.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor,
            constant: -4
        )
        // A reused cell can retain its previous height until the collection applies new layout attributes.
        // Let this edge yield temporarily instead of breaking image and quote content constraints.
        bubbleBottomConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            avatarView.bottomAnchor.constraint(equalTo: bubbleContainerView.bottomAnchor),
            avatarWidthConstraint!,
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            botAvatarImageView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            botAvatarImageView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            botAvatarImageView.widthAnchor.constraint(equalToConstant: 24),
            botAvatarImageView.heightAnchor.constraint(equalToConstant: 24),

            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            dateSeparatorLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            dateSeparatorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateSeparatorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dateSeparatorLabel.heightAnchor.constraint(equalToConstant: 16),
            bubbleTopConstraint!,
            bubbleBottomConstraint,
            bubbleWidthConstraint!
        ])
    }

    /// Applies message content, avatar visibility, author visibility, theme, manager identity, and interaction callbacks.
    package func configure(
        message: ConsultantMessage,
        dateSeparatorText: String? = nil,
        showsAvatar: Bool? = nil,
        showsAuthor: Bool = true,
        roundsAllCorners: Bool = false,
        theme: ConsultantTheme = .defaultTheme,
        managerIdentity: ManagerIdentity? = nil,
        imageWorkers: [String] = [],
        loadingFilePreviewIDs: Set<String> = [],
        loadingImagePreviewIDs: Set<String> = [],
        isContactFormSubmitting: Bool = false,
        onImagePreview: (([ImagePreviewItem], Int) -> Void)? = nil,
        onFilePreview: (([FilePreviewItem], Int) -> Void)? = nil,
        onContactFormSubmit: ((ContactFormSubmitData) -> Void)? = nil,
        onPersonalDataLinkTap: ((URL) -> Void)? = nil,
        personalDataLink: URL? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        onQuoteTap: ((String) -> Void)? = nil
    ) {
        currentMessage = message
        currentTheme = theme
        dateSeparatorLabel.text = dateSeparatorText
        dateSeparatorLabel.isHidden = dateSeparatorText == nil
        dateSeparatorLabel.textColor = theme.isDarkTheme
            ? theme.messageDateColor
            : UIColor(red: 99 / 255, green: 111 / 255, blue: 127 / 255, alpha: 0.74)
        bubbleTopConstraint?.constant = 4 + (dateSeparatorText == nil ? 0 : Self.dateSeparatorHeight)

        let bubbleKind = Self.bubbleKind(for: message)
        let isContactFormMessage = bubbleKind == .contactForm
        let isOutgoing = message.fromMe == true
        let resolvedShowsAvatar = showsAvatar ?? (message.fromMe != true)
        let shouldShowAvatar = !isOutgoing && resolvedShowsAvatar && !isContactFormMessage
        let shouldShowAuthor = showsAuthor && !isContactFormMessage
        let reservesAvatarSpace = !isOutgoing && !isContactFormMessage
        let canUseManagerIdentity = !isOutgoing && !isContactFormMessage
        let messageManagerIdentity = canUseManagerIdentity ? managerIdentity : nil
        let authorNameOverride = messageManagerIdentity?.displayName
        currentReservesAvatarSpace = reservesAvatarSpace
        currentShowsAuthor = shouldShowAuthor
        currentAuthorNameOverride = authorNameOverride

        configureAvatar(
            message: message,
            isHidden: !shouldShowAvatar,
            reservesSpace: reservesAvatarSpace,
            managerIdentity: messageManagerIdentity
        )
        configurePosition(
            isOutgoing: isOutgoing,
            reservesAvatarSpace: reservesAvatarSpace,
            isContactFormMessage: isContactFormMessage
        )

        textMessageBubbleView.isHidden = bubbleKind != .text
        imageMessageBubbleView.isHidden = bubbleKind != .image
        fileMessageBubbleView.isHidden = bubbleKind != .file
        quoteMessageBubbleView.isHidden = bubbleKind != .quote
        productMessageBubbleView.isHidden = bubbleKind != .product
        orderMessageBubbleView.isHidden = bubbleKind != .order
        contactFormMessageBubbleView.isHidden = bubbleKind != .contactForm

        switch bubbleKind {
        case .image:
            imageMessageBubbleView.onImagePreview = onImagePreview
            imageMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride,
                imageWorkers: imageWorkers,
                loadingImagePreviewIDs: loadingImagePreviewIDs
            )
        case .file:
            fileMessageBubbleView.onFilePreview = onFilePreview
            fileMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride,
                loadingFilePreviewIDs: loadingFilePreviewIDs
            )
        case .quote:
            quoteMessageBubbleView.onQuoteTap = {
                guard let id = message.quoteID?.value else { return }
                onQuoteTap?(id)
            }
            quoteMessageBubbleView.onLinkTap = onLinkTap
            quoteMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride
            )
        case .product:
            productMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride,
                imageWorkers: imageWorkers
            )
        case .order:
            orderMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride
            )
        case .contactForm:
            contactFormMessageBubbleView.onSubmit = onContactFormSubmit
            contactFormMessageBubbleView.onPersonalDataLinkTap = onPersonalDataLinkTap
            contactFormMessageBubbleView.configure(
                message: message,
                roundsAllCorners: roundsAllCorners,
                isSubmitting: isContactFormSubmitting,
                theme: theme,
                personalDataLink: personalDataLink
            )
        case .text:
            textMessageBubbleView.onLinkTap = onLinkTap
            textMessageBubbleView.configure(
                message: message,
                showsAuthor: shouldShowAuthor,
                roundsAllCorners: roundsAllCorners,
                theme: theme,
                authorNameOverride: authorNameOverride
            )
        }

        updateBubbleWidth(
            for: message,
            reservesAvatarSpace: reservesAvatarSpace
        )
        showBubble(for: bubbleKind)
    }

    private func removeActiveBubble() {
        NSLayoutConstraint.deactivate(activeBubbleConstraints)
        activeBubbleConstraints = []
        activeBubbleView?.removeFromSuperview()
        activeBubbleView = nil
    }

    private func showBubble(for kind: MessageBubbleKind) {
        let bubble: UIView
        switch kind {
        case .text: bubble = textMessageBubbleView
        case .image: bubble = imageMessageBubbleView
        case .file: bubble = fileMessageBubbleView
        case .quote: bubble = quoteMessageBubbleView
        case .product: bubble = productMessageBubbleView
        case .order: bubble = orderMessageBubbleView
        case .contactForm: bubble = contactFormMessageBubbleView
        }
        guard activeBubbleView !== bubble else { return }

        // Hidden views still participate in Auto Layout. Only the current message
        // may constrain the container's size, especially after cell reuse.
        removeActiveBubble()
        bubbleContainerView.addSubview(bubble)
        activeBubbleView = bubble
        activeBubbleConstraints = [
            bubble.topAnchor.constraint(equalTo: bubbleContainerView.topAnchor),
            bubble.leadingAnchor.constraint(equalTo: bubbleContainerView.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: bubbleContainerView.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: bubbleContainerView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(activeBubbleConstraints)
    }

    /// Updates the visible contact form submitting state without rebuilding the whole message cell.
    package func setContactFormSubmitting(_ isSubmitting: Bool) {
        guard currentMessage?.contactForm != nil else {
            return
        }
        contactFormMessageBubbleView.setSubmitting(isSubmitting)
    }

    /// Refreshes delivery metadata for the bubble type represented by the provided message.
    package func updateDeliveryStatus(
        message: ConsultantMessage,
        theme: ConsultantTheme? = nil
    ) {
        currentMessage = message
        let theme = theme ?? currentTheme

        switch Self.bubbleKind(for: message) {
        case .image:
            imageMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .file:
            fileMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .quote:
            quoteMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .product:
            productMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .order:
            orderMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .text:
            textMessageBubbleView.updateDeliveryStatus(message: message, theme: theme)
        case .contactForm:
            break
        }
    }

    private func configureAvatar(
        message: ConsultantMessage,
        isHidden: Bool,
        reservesSpace: Bool,
        managerIdentity: ManagerIdentity?
    ) {
        avatarImageLoadTask?.cancel()
        avatarImageLoadTask = nil
        currentAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarImageView.contentMode = .scaleAspectFill
        botAvatarImageView.isHidden = true
        avatarLabel.isHidden = false
        avatarView.isHidden = isHidden
        avatarWidthConstraint?.constant = reservesSpace ? 36 : 0
        avatarLabel.text = initials(from: managerIdentity?.displayName) ?? initials(from: message.user)
        avatarView.backgroundColor = currentTheme.consultantBubbleColor
        avatarLabel.textColor = currentTheme.primaryTextColor
        botAvatarImageView.tintColor = currentTheme.isDarkTheme ? .white : .black

        if message.isVirtualSupportMessage,
           managerIdentity?.logoURL == nil,
           botAvatarImageView.image != nil {
            botAvatarImageView.isHidden = false
            avatarLabel.isHidden = true
            return
        }

        guard !isHidden, let url = avatarURL(for: message, managerIdentity: managerIdentity) else {
            return
        }

        currentAvatarURL = url
        avatarImageLoadTask = ImageLoader.shared.loadImage(from: url) { [weak self] image in
            guard self?.currentAvatarURL == url else {
                return
            }

            self?.avatarImageView.image = image
            self?.avatarImageView.isHidden = image == nil
            self?.avatarLabel.isHidden = image != nil
        }
    }

    private func avatarURL(
        for message: ConsultantMessage,
        managerIdentity: ManagerIdentity?
    ) -> URL? {
        let fallbackAvatarURL = message.user?.avatar?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .flatMap(URL.init(string:))

        return managerIdentity?.logoURL ?? fallbackAvatarURL
    }

    private func configurePosition(
        isOutgoing: Bool,
        reservesAvatarSpace: Bool,
        isContactFormMessage: Bool
    ) {
        bubbleIncomingLeadingConstraint?.isActive = false
        bubbleIncomingNoAvatarLeadingConstraint?.isActive = false
        bubbleOutgoingTrailingConstraint?.isActive = false
        bubbleIncomingTrailingConstraint?.isActive = false
        bubbleOutgoingLeadingConstraint?.isActive = false
        bubbleCenteredXConstraint?.isActive = false

        if isContactFormMessage {
            bubbleCenteredXConstraint?.isActive = true
            return
        }

        if isOutgoing {
            bubbleOutgoingTrailingConstraint?.isActive = true
            bubbleOutgoingLeadingConstraint?.isActive = true
        } else {
            if reservesAvatarSpace {
                bubbleIncomingLeadingConstraint?.isActive = true
            } else {
                bubbleIncomingNoAvatarLeadingConstraint?.isActive = true
            }
            bubbleIncomingTrailingConstraint?.isActive = true
        }
    }

    private func updateBubbleWidth(
        for message: ConsultantMessage,
        reservesAvatarSpace: Bool
    ) {
        let collectionWidth = max(contentView.bounds.width, bounds.width)

        guard collectionWidth > 0 else {
            return
        }

        bubbleWidthConstraint?.constant = Self.preferredBubbleWidth(
            for: message,
            collectionWidth: collectionWidth,
            reservesAvatarSpace: reservesAvatarSpace,
            showsAuthor: currentShowsAuthor,
            authorNameOverride: currentAuthorNameOverride
        )
    }

    private func initials(from user: MessageUser?) -> String {
        let initials = [user?.firstName, user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).first }
            .map(String.init)
            .joined()
            .uppercased()
        return initials.isEmpty
            ? ConsultantLocalization.messageAuthorConsultantInitial.localized
            : initials
    }

    private func initials(from displayName: String?) -> String? {
        guard let displayName else {
            return nil
        }

        let parts = displayName
            .split { $0.isWhitespace || $0.isNewline }
            .prefix(2)
        let initials = parts
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()

        return initials.isEmpty ? nil : initials
    }
}

package extension MessageCollectionViewCell {

    private enum MessageBubbleKind {
        case contactForm
        case image
        case file
        case product
        case order
        case quote
        case text
    }

    private static func bubbleKind(for message: ConsultantMessage) -> MessageBubbleKind {
        switch message.messageType {
        case .contactForm where message.contactForm != nil:
            return .contactForm
        case .image:
            return .image
        case .file:
            return .file
        case .product where message.product != nil:
            return .product
        case .order where message.order != nil:
            return .order
        default:
            break
        }

        if message.contactForm != nil {
            return .contactForm
        }

        if message.quotePreview != nil {
            return .quote
        }

        return .text
    }

    /// Calculates the bubble width for the message type, avatar reservation, and author visibility.
    static func preferredBubbleWidth(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        reservesAvatarSpace: Bool? = nil,
        showsAuthor: Bool = true,
        authorNameOverride: String? = nil
    ) -> CGFloat {
        let bubbleKind = bubbleKind(for: message)
        let isOutgoing = message.fromMe == true
        let resolvedReservesAvatarSpace = reservesAvatarSpace ?? (message.fromMe != true)
        let shouldReserveAvatarSpace = !isOutgoing && resolvedReservesAvatarSpace && bubbleKind != .contactForm
        let maxBubbleWidth = maximumBubbleWidth(
            collectionWidth: collectionWidth,
            reservesAvatarSpace: shouldReserveAvatarSpace
        )

        switch bubbleKind {
        case .contactForm:
            return ContactFormMessageLayout.preferredBubbleWidth(
                maxBubbleWidth: maxBubbleWidth
            )
        case .image:
            let imageBubbleWidth = ImageMessageLayout.preferredBubbleWidth(
                maxBubbleWidth: maxBubbleWidth,
                sourceSizes: message.imageDisplayItems.map(\.sourceImageSize)
            )
            let authorBubbleWidth = imageAuthorBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )

            return max(imageBubbleWidth, authorBubbleWidth)
        case .file:
            return fileBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )
        case .product:
            return productBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )
        case .order:
            return orderBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )
        case .quote:
            return quoteBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )
        case .text:
            return textBubbleWidth(
                for: message,
                maxBubbleWidth: maxBubbleWidth,
                showsAuthor: showsAuthor,
                authorNameOverride: isOutgoing ? nil : authorNameOverride
            )
        }
    }

    private static func maximumBubbleWidth(
        collectionWidth: CGFloat,
        reservesAvatarSpace: Bool
    ) -> CGFloat {
        guard collectionWidth > 0 else {
            return 1
        }

        let layoutMaxWidth = collectionWidth * MessageLayout.bubbleMaxWidthMultiplier
        let horizontalInsets: CGFloat = 32
        let avatarWidth: CGFloat = reservesAvatarSpace ? 36 : 0
        let avatarSpacing: CGFloat = reservesAvatarSpace ? 8 : 0
        let availableWidth = collectionWidth - horizontalInsets - avatarWidth - avatarSpacing

        return max(1, min(layoutMaxWidth, availableWidth))
    }

    private static func textBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let isOutgoing = message.fromMe == true
        let messageText = message.content?.isEmpty == false
            ? message.content
            : message.messageType.map { "[\($0.rawValue)]" }
        let messageWidth = width(
            for: messageText,
            maxWidth: maxContentWidth,
            font: MessageBubbleStyle.messageFont
        )
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = !showsAuthor
            ? 0
            : width(
                for: authorName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.authorFont
            )
        let metadataWidth = MetadataView.preferredWidth(
            for: message,
            maxWidth: maxContentWidth
        )
        let contentWidth = min(maxContentWidth, max(messageWidth, authorWidth, metadataWidth))

        return ceil(max(52, contentWidth + MessageLayout.bubbleHorizontalInset * 2))
    }

    private static func imageAuthorBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        guard showsAuthor else {
            return 0
        }

        let isOutgoing = message.fromMe == true
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.compactSpacing * 2)
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = width(
            for: authorName,
            maxWidth: maxContentWidth,
            font: MessageBubbleStyle.authorFont
        )

        return ceil(authorWidth + MessageLayout.compactSpacing * 2)
    }

    private static func fileBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let isOutgoing = message.fromMe == true
        let titleWidths = message.fileDisplayItems.map {
            width(
                for: $0.displayName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.semiboldMediumFont
            )
        }
        let sizeWidths = message.fileDisplayItems.map {
            width(
                for: $0.sizeLabel,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.regularSmallFont
            )
        }
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = !showsAuthor
            ? 0
            : width(
                for: authorName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.authorFont
            )
        let metadataWidth = MetadataView.preferredWidth(
            for: message,
            maxWidth: maxContentWidth
        )

        return FileMessageLayout.preferredBubbleWidth(
            maxBubbleWidth: maxBubbleWidth,
            fileNameWidths: titleWidths,
            fileSizeWidths: sizeWidths,
            authorWidth: authorWidth,
            metadataWidth: metadataWidth
        )
    }

    private static func quoteBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let isOutgoing = message.fromMe == true
        let bodyWidth = width(
            for: message.content,
            maxWidth: maxContentWidth,
            font: MessageBubbleStyle.messageFont
        )
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = !showsAuthor
            ? 0
            : width(
                for: authorName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.authorFont
            )
        let quoteWidth = quotePreviewWidth(
            for: message.quotePreview,
            maxWidth: maxContentWidth
        )
        let metadataWidth = MetadataView.preferredWidth(
            for: message,
            maxWidth: maxContentWidth
        )

        return QuoteMessageLayout.preferredBubbleWidth(
            maxBubbleWidth: maxBubbleWidth,
            authorWidth: authorWidth,
            bodyWidth: bodyWidth,
            quoteWidth: quoteWidth,
            metadataWidth: metadataWidth
        )
    }

    private static func productBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let isOutgoing = message.fromMe == true
        let extraTextInset = ProductMessageLayout.additionalTextTrailingInset(isOutgoing: isOutgoing)
        let maxTextWidth = max(1, maxContentWidth - extraTextInset)
        let titleWidth = width(
            for: message.productDisplayName,
            maxWidth: maxTextWidth,
            font: MessageBubbleStyle.messageFont
        )
        let priceWidth = width(
            for: message.productPriceLabel,
            maxWidth: maxTextWidth,
            font: MessageBubbleStyle.semiboldCompactFont
        )
        let quantityWidth = width(
            for: message.productQuantityLabel,
            maxWidth: maxTextWidth,
            font: MessageBubbleStyle.regularCompactFont
        )
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = !showsAuthor
            ? 0
            : width(
                for: authorName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.authorFont
            )
        let metadataWidth = MetadataView.preferredWidth(
            for: message,
            maxWidth: maxContentWidth
        )

        return ProductMessageLayout.preferredBubbleWidth(
            maxBubbleWidth: maxBubbleWidth,
            titleWidth: titleWidth,
            priceWidth: priceWidth,
            quantityWidth: quantityWidth,
            authorWidth: authorWidth,
            metadataWidth: metadataWidth,
            minimumContentWidth: isOutgoing ? ProductMessageLayout.defaultContentWidth : 0,
            additionalTextTrailingInset: extraTextInset
        )
    }

    private static func orderBubbleWidth(
        for message: ConsultantMessage,
        maxBubbleWidth: CGFloat,
        showsAuthor: Bool,
        authorNameOverride: String?
    ) -> CGFloat {
        let maxContentWidth = max(1, maxBubbleWidth - MessageLayout.bubbleHorizontalInset * 2)
        let isOutgoing = message.fromMe == true
        let orderNumberWidth = width(
            for: message.orderNumberLabel,
            maxWidth: maxContentWidth,
            font: MessageBubbleStyle.semiboldMediumFont
        )
        let itemWidth = message.orderDisplayItems.reduce(CGFloat(0)) { result, item in
            let titleWidth = width(
                for: "\(item.numberLabel) \(item.name)",
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.messageFont
            )
            let detailsWidth = width(
                for: item.details,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.regularCompactFont
            )

            return max(result, titleWidth, detailsWidth)
        }
        let fieldWidth = message.orderDisplayFields.reduce(CGFloat(0)) { result, field in
            let titleWidth = width(
                for: field.title,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.semiboldMediumFont
            )
            let valueWidth = width(
                for: field.value,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.regularCompactFont
            )

            return max(result, titleWidth, valueWidth)
        }
        let authorName = authorNameOverride
            ?? message.user?.displayName(isOutgoing: isOutgoing)
            ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
        let authorWidth = !showsAuthor
            ? 0
            : width(
                for: authorName,
                maxWidth: maxContentWidth,
                font: MessageBubbleStyle.authorFont
            )
        let metadataWidth = MetadataView.preferredWidth(
            for: message,
            maxWidth: maxContentWidth
        )

        return OrderMessageLayout.preferredBubbleWidth(
            maxBubbleWidth: maxBubbleWidth,
            orderContentWidth: max(orderNumberWidth, itemWidth, fieldWidth),
            authorWidth: authorWidth,
            metadataWidth: metadataWidth,
            minimumContentWidth: isOutgoing ? OrderMessageLayout.defaultContentWidth : 0
        )
    }

    private static func quotePreviewWidth(
        for preview: MessageQuotePreview?,
        maxWidth: CGFloat
    ) -> CGFloat {
        guard let preview else {
            return 0
        }

        let leadingWidth: CGFloat

        switch preview {
        case .text(let text):
            leadingWidth = QuoteMessageLayout.quoteBarWidth
                + QuoteMessageLayout.quoteBarContentSpacing
            let textWidth = width(
                for: text,
                maxWidth: max(1, maxWidth - leadingWidth),
                font: MessageBubbleStyle.regularSmallFont
            )

            return min(maxWidth, ceil(leadingWidth + textWidth))
        case .attachments(let items, let isImage, let text, let author):
            let leadingWidth = QuoteMessageLayout.quoteBarWidth + QuoteMessageLayout.quoteBarContentSpacing
            let thumbnailWidth = QuoteMessageLayout.thumbnailSize + QuoteMessageLayout.thumbnailSpacing
            let labelMaxWidth = max(1, maxWidth - leadingWidth - thumbnailWidth)
            let authorWidth = width(for: author, maxWidth: labelMaxWidth, font: MessageBubbleStyle.authorFont)
            let titleWidth = items.map { item in
                width(
                    for: isImage ? ConsultantLocalization.messageQuotePhoto.localized
                        : item.caption ?? ConsultantLocalization.commonFile.localized,
                    maxWidth: labelMaxWidth,
                    font: MessageBubbleStyle.regularSmallFont
                )
            }.max() ?? 0
            let attachmentWidth = thumbnailWidth + max(authorWidth, titleWidth)
            let textWidth = width(
                for: text,
                maxWidth: max(1, maxWidth - leadingWidth),
                font: MessageBubbleStyle.regularSmallFont
            )
            return min(maxWidth, ceil(leadingWidth + max(attachmentWidth, textWidth)))
        }
    }

    private static func width(
        for text: String?,
        maxWidth: CGFloat,
        font: UIFont
    ) -> CGFloat {
        guard let text, !text.isEmpty else {
            return 0
        }

        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, maxWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).width
        )
    }

    /// Calculates the full cell height for the message type and collection width.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool = true
    ) -> CGFloat {
        switch bubbleKind(for: message) {
        case .contactForm:
            return ContactFormMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth
            )
        case .image:
            return ImageMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        case .file:
            return FileMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        case .product:
            return ProductMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        case .order:
            return OrderMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        case .quote:
            return QuoteMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        case .text:
            return TextMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        }
    }
}
