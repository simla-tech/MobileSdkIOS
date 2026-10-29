import UIKit

/// Renders a plain text message with optional author and delivery metadata.
package final class TextMessageBubbleView: UIView {

    package var onLinkTap: ((URL) -> Void)? {
        didSet {
            messageLabel.onLinkTap = onLinkTap
        }
    }

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = MessageLayout.bubbleContentSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var authorLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.authorFont
        label.textColor = MessageBubbleStyle.textColor
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "messageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var messageLabel: LinkedMessageTextView = {
        let label = LinkedMessageTextView()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "messageTextLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var metadataView: MetadataView = {
        let view = MetadataView()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var metadataMinimumHeightConstraint = metadataView.heightAnchor.constraint(
        greaterThanOrEqualToConstant: MessageLayout.secondaryLineHeight
    )

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Resets text, author, and metadata before the view is reused by a cell.
    package func prepareForReuse() {
        authorLabel.text = nil
        messageLabel.prepareForReuse()
        metadataView.prepareForReuse()
        authorLabel.isHidden = false
        onLinkTap = nil
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        backgroundColor = .clear

        addSubview(bubbleView)

        bubbleView.contentView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(authorLabel)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(metadataView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),

            metadataMinimumHeightConstraint
        ])
    }

    /// Applies message text, author visibility, bubble shape, colors, and metadata.
    package func configure(
        message: ConsultantMessage,
        showsAuthor: Bool = true,
        roundsAllCorners: Bool = false,
        theme: ConsultantTheme = .defaultTheme,
        authorNameOverride: String? = nil
    ) {
        let isOutgoing = message.fromMe == true
        let textColor = MessageBubbleStyle.textColor(
            isOutgoing: isOutgoing,
            theme: theme
        )
        let secondaryColor = MessageBubbleStyle.secondaryColor(
            isOutgoing: isOutgoing,
            theme: theme
        )

        bubbleView.configure(
            isOutgoing: isOutgoing,
            roundsAllCorners: roundsAllCorners,
            theme: theme
        )
        authorLabel.text = showsAuthor
            ? authorNameOverride
                ?? message.user?.displayName(isOutgoing: isOutgoing)
                ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
            : nil
        authorLabel.isHidden = !showsAuthor
        authorLabel.textColor = textColor
        let messageText = message.content?.isEmpty == false
            ? message.content
            : message.messageType.map { "[\($0.rawValue)]" }
        messageLabel.configure(
            text: messageText,
            textColor: textColor,
            font: MessageBubbleStyle.messageFont,
            linkColor: isOutgoing ? textColor : .systemBlue
        )
        metadataView.configure(
            message: message,
            tintColor: secondaryColor,
            timestampAccessibilityIdentifier: "messageMetadataLabel",
            statusAccessibilityIdentifier: "messageStatusImageView"
        )
        metadataMinimumHeightConstraint.constant = metadataView.isHidden
            ? 0
            : MessageLayout.secondaryLineHeight
    }

    /// Refreshes only the outgoing delivery status without rebuilding the whole bubble.
    package func updateDeliveryStatus(
        message: ConsultantMessage,
        theme: ConsultantTheme = .defaultTheme
    ) {
        metadataView.updateDeliveryStatus(
            message: message,
            tintColor: MessageBubbleStyle.secondaryColor(
                isOutgoing: message.fromMe == true,
                theme: theme
            ),
            statusAccessibilityIdentifier: "messageStatusImageView"
        )
    }

}

package extension TextMessageBubbleView {

    /// Calculates the height needed to render a text message in the current collection width.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool = true
    ) -> CGFloat {
        guard collectionWidth > 0 else {
            return 52
        }

        let maxTextWidth = TextMessageLayout.maxTextWidth(collectionWidth: collectionWidth)
        let isOutgoing = message.fromMe == true
        let messageText = message.content?.isEmpty == false
            ? message.content ?? ""
            : message.messageType.map { "[\($0.rawValue)]" } ?? ""
        let messageHeight = height(
            for: messageText,
            width: maxTextWidth,
            font: MessageBubbleStyle.messageFont
        )

        return TextMessageLayout.preferredHeight(
            messageTextHeight: messageHeight,
            isOutgoing: isOutgoing,
            showsAuthor: showsAuthor,
            showsMetadata: MessageMetadataFormatter.metadataText(for: message) != nil
                || (isOutgoing && MessageDeliveryStatus(messageStatus: message.status) != .none)
        )
    }

    private static func height(for text: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard !text.isEmpty else {
            return ceil(font.lineHeight)
        }

        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
        )
    }
}
