import UIKit

/// Renders one or more image attachments with optional author and metadata overlay.
package final class ImageMessageBubbleView: UIView {

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView(
            contentInsets: UIEdgeInsets(
                top: MessageLayout.compactSpacing,
                left: MessageLayout.compactSpacing,
                bottom: MessageLayout.compactSpacing,
                right: MessageLayout.compactSpacing
            )
        )
        view.accessibilityIdentifier = "imageMessageBubbleView"
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
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "imageMessageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var imagesStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .leading
        view.distribution = .fill
        view.spacing = MessageLayout.contentItemSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var imageItemViews: [ImageMessageItemView] = []
    /// Called when the user taps an image attachment that can be previewed.
    package var onImagePreview: (([ImagePreviewItem], Int) -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    package override func layoutSubviews() {
        super.layoutSubviews()
        updateImageSize()
    }

    /// Clears image item views, preview callbacks, and author state before reuse.
    package func prepareForReuse() {
        authorLabel.text = nil
        authorLabel.isHidden = false
        onImagePreview = nil
        removeImageItemViews()
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
        contentStackView.addArrangedSubview(imagesStackView)
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
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor)
        ])
    }

    /// Applies image attachments, author visibility, bubble shape, loading state, and image worker hosts.
    package func configure(
        message: ConsultantMessage,
        showsAuthor: Bool = true,
        roundsAllCorners: Bool = false,
        theme: ConsultantTheme = .defaultTheme,
        authorNameOverride: String? = nil,
        imageWorkers: [String] = [],
        loadingImagePreviewIDs: Set<String> = []
    ) {
        let isOutgoing = message.fromMe == true
        let textColor = MessageBubbleStyle.textColor(
            isOutgoing: isOutgoing,
            theme: theme
        )

        bubbleView.configure(
            isOutgoing: isOutgoing,
            roundsAllCorners: roundsAllCorners,
            theme: theme
        )
        bubbleView.setContentInsets(
            UIEdgeInsets(
                top: showsAuthor
                    ? MessageLayout.bubbleVerticalInset
                    : MessageLayout.compactSpacing,
                left: MessageLayout.compactSpacing,
                bottom: MessageLayout.compactSpacing,
                right: MessageLayout.compactSpacing
            )
        )
        authorLabel.text = showsAuthor
            ? authorNameOverride
                ?? message.user?.displayName(isOutgoing: isOutgoing)
                ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
            : nil
        authorLabel.isHidden = !showsAuthor
        authorLabel.textColor = textColor
        configureImageItems(
            message: message,
            imageWorkers: imageWorkers,
            loadingImagePreviewIDs: loadingImagePreviewIDs
        )
        updateImageSize()
    }

    /// Refreshes delivery metadata on the last image item, where the metadata overlay is rendered.
    package func updateDeliveryStatus(
        message: ConsultantMessage,
        theme: ConsultantTheme = .defaultTheme
    ) {
        imageItemViews.last?.updateDeliveryStatus(
            message: message,
            statusAccessibilityIdentifier: "imageMessageStatusImageView"
        )
    }

    private func updateImageSize() {
        let maxBubbleWidth = max(1, bounds.width)
        imageItemViews.forEach { $0.updateSize(maxBubbleWidth: maxBubbleWidth) }
    }

    private func configureImageItems(
        message: ConsultantMessage,
        imageWorkers: [String],
        loadingImagePreviewIDs: Set<String>
    ) {
        removeImageItemViews()

        let previewItems = message.imagePreviewItems
        var nextPreviewIndex = 0

        for (index, item) in message.imageDisplayItems.enumerated() {
            let itemView = ImageMessageItemView()
            let previewIndex: Int?
            if item.urlString.flatMap(URL.init(string:)) == nil {
                previewIndex = nil
            } else {
                previewIndex = nextPreviewIndex
                nextPreviewIndex += 1
            }
            itemView.translatesAutoresizingMaskIntoConstraints = false
            itemView.onTap = { [weak self] in
                guard let previewIndex else {
                    return
                }

                self?.onImagePreview?(previewItems, previewIndex)
            }
            itemView.configure(
                item: item,
                message: message,
                showsMetadata: index == message.imageDisplayItems.count - 1,
                imageWorkers: imageWorkers,
                isTapEnabled: previewIndex != nil,
                isLoading: item.id.map { loadingImagePreviewIDs.contains($0) } ?? false
            )
            imagesStackView.addArrangedSubview(itemView)
            imageItemViews.append(itemView)
        }
    }

    private func removeImageItemViews() {
        for itemView in imageItemViews {
            itemView.prepareForReuse()
            imagesStackView.removeArrangedSubview(itemView)
            itemView.removeFromSuperview()
        }

        imageItemViews.removeAll()
    }

}

package extension ImageMessageBubbleView {
    /// Calculates the height needed for all image attachments in the message.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool = true
    ) -> CGFloat {
        ImageMessageLayout.preferredHeight(
            collectionWidth: collectionWidth,
            sourceSizes: message.imageDisplayItems.map(\.sourceImageSize),
            showsAuthor: showsAuthor
        )
    }

    /// Calculates the fallback height for an image bubble without message-specific source sizes.
    static func preferredHeight(collectionWidth: CGFloat) -> CGFloat {
        ImageMessageLayout.preferredHeight(
            collectionWidth: collectionWidth,
            showsAuthor: false
        )
    }
}
