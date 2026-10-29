import UIKit

/// Renders a quote message with a quoted preview, optional body text, author, and metadata.
package final class QuoteMessageBubbleView: UIView {

    package var onQuoteTap: (() -> Void)?

    package var onLinkTap: ((URL) -> Void)? {
        didSet {
            messageLabel.onLinkTap = onLinkTap
        }
    }

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView(contentInsets: UIEdgeInsets(
            top: QuoteMessageLayout.verticalInset,
            left: MessageLayout.bubbleHorizontalInset,
            bottom: QuoteMessageLayout.verticalInset,
            right: MessageLayout.bubbleHorizontalInset
        ))
        view.accessibilityIdentifier = "quoteMessageBubbleView"
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
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "quoteMessageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var quotePreviewView: QuotePreviewView = {
        let view = QuotePreviewView()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleQuoteTap)))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var messageLabel: LinkedMessageTextView = {
        let label = LinkedMessageTextView()
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "quoteMessageBodyLabel"
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
    private var quotePreviewHeightConstraint: NSLayoutConstraint?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Resets quote preview, body text, author, and metadata before reuse.
    package func prepareForReuse() {
        authorLabel.text = nil
        authorLabel.isHidden = false
        quotePreviewView.prepareForReuse()
        messageLabel.prepareForReuse()
        messageLabel.isHidden = false
        metadataView.prepareForReuse()
        onLinkTap = nil
        onQuoteTap = nil
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
        contentStackView.addArrangedSubview(quotePreviewView)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(metadataView)
    }

    private func setupConstraints() {
        quotePreviewHeightConstraint = quotePreviewView.heightAnchor.constraint(
            equalToConstant: QuoteMessageLayout.quoteTextMinHeight
        )

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),
            quotePreviewHeightConstraint!,

            metadataView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: MessageLayout.secondaryLineHeight
            )
        ])
    }

    /// Applies quoted content, optional body text, author visibility, bubble shape, colors, and metadata.
    package func configure(
        message: ConsultantMessage,
        showsAuthor: Bool,
        roundsAllCorners: Bool,
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

        if let quotePreview = message.quotePreview {
            quotePreviewView.configure(preview: quotePreview, textColor: textColor)
            quotePreviewView.isHidden = false
            quotePreviewHeightConstraint?.constant = QuoteMessageLayout.quotePreviewHeight(
                for: quotePreview
            )
        } else {
            quotePreviewView.isHidden = true
        }

        let messageText = message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        messageLabel.configure(
            text: messageText,
            textColor: textColor,
            font: MessageBubbleStyle.messageFont,
            linkColor: isOutgoing ? textColor : .systemBlue
        )
        messageLabel.isHidden = messageText?.isEmpty != false
        metadataView.configure(
            message: message,
            tintColor: secondaryColor,
            timestampAccessibilityIdentifier: "quoteMessageMetadataLabel",
            statusAccessibilityIdentifier: "quoteMessageStatusImageView"
        )
    }

    @objc private func handleQuoteTap() {
        onQuoteTap?()
    }

    /// Refreshes only the outgoing delivery status without rebuilding quote content.
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
            statusAccessibilityIdentifier: "quoteMessageStatusImageView"
        )
    }

}

package extension QuoteMessageBubbleView {
    /// Calculates the height needed for a quote message, falling back to text message sizing when no preview exists.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool
    ) -> CGFloat {
        guard let preview = message.quotePreview else {
            return TextMessageBubbleView.preferredHeight(
                for: message,
                collectionWidth: collectionWidth,
                showsAuthor: showsAuthor
            )
        }

        let maxBodyWidth = max(
            1,
            collectionWidth * MessageLayout.bubbleMaxWidthMultiplier
                - MessageLayout.bubbleHorizontalInset * 2
        )
        let bodyText = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyHeight = bodyText.isEmpty
            ? 0
            : height(
                for: bodyText,
                width: maxBodyWidth,
                font: MessageBubbleStyle.messageFont
            )

        return QuoteMessageLayout.preferredHeight(
            bodyHeight: bodyHeight,
            preview: preview,
            showsAuthor: showsAuthor
        )
    }

    private static func height(for text: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard !text.isEmpty else {
            return 0
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
