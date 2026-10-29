import UIKit

/// Renders one or more file attachments with optional author and delivery metadata.
package final class FileMessageBubbleView: UIView {

    private lazy var bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = MessageLayout.contentCornerRadius
        view.clipsToBounds = true
        view.accessibilityIdentifier = "fileMessageBubbleView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = MessageLayout.compactSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var authorLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.authorFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "fileMessageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var filesStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = MessageLayout.compactSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var metadataView: MetadataView = {
        let view = MetadataView()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var fileRowViews: [FileMessageItemView] = []
    private var contentStackTopConstraint: NSLayoutConstraint?
    /// Called when the user taps a downloadable file row that can be previewed.
    package var onFilePreview: (([FilePreviewItem], Int) -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Clears file rows, preview callbacks, author text, and metadata before reuse.
    package func prepareForReuse() {
        authorLabel.text = nil
        authorLabel.isHidden = false
        onFilePreview = nil
        removeFileRows()
        metadataView.prepareForReuse()
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        backgroundColor = .clear

        addSubview(bubbleView)

        bubbleView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(authorLabel)
        contentStackView.addArrangedSubview(filesStackView)
        contentStackView.addArrangedSubview(metadataView)
    }

    private func setupConstraints() {
        let contentStackTopConstraint = contentStackView.topAnchor.constraint(
            equalTo: bubbleView.topAnchor,
            constant: MessageLayout.bubbleVerticalInset
        )
        self.contentStackTopConstraint = contentStackTopConstraint

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackTopConstraint,
            contentStackView.leadingAnchor.constraint(
                equalTo: bubbleView.leadingAnchor,
                constant: MessageLayout.bubbleHorizontalInset
            ),
            contentStackView.trailingAnchor.constraint(
                equalTo: bubbleView.trailingAnchor,
                constant: -MessageLayout.bubbleHorizontalInset
            ),
            contentStackView.bottomAnchor.constraint(
                equalTo: bubbleView.bottomAnchor,
                constant: -FileMessageLayout.bubbleBottomInset
            ),

            metadataView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: MessageLayout.secondaryLineHeight
            )
        ])
    }

    /// Applies file rows, author visibility, bubble shape, colors, loading state, and metadata.
    package func configure(
        message: ConsultantMessage,
        showsAuthor: Bool = true,
        roundsAllCorners: Bool = false,
        theme: ConsultantTheme = .defaultTheme,
        authorNameOverride: String? = nil,
        loadingFilePreviewIDs: Set<String> = []
    ) {
        let isOutgoing = message.fromMe == true

        configureBubble(
            isOutgoing: isOutgoing,
            roundsAllCorners: roundsAllCorners,
            theme: theme
        )
        configureColors(
            isOutgoing: isOutgoing,
            theme: theme
        )

        authorLabel.text = showsAuthor
            ? authorNameOverride
                ?? message.user?.displayName(isOutgoing: isOutgoing)
                ?? MessageUser.fallbackDisplayName(isOutgoing: isOutgoing)
            : nil
        authorLabel.isHidden = !showsAuthor
        contentStackTopConstraint?.constant = showsAuthor
            ? MessageLayout.bubbleVerticalInset
            : FileMessageLayout.bubbleTopInsetWithoutAuthor
        configureFileRows(
            items: message.fileDisplayItems,
            previewItems: message.filePreviewItems,
            isOutgoing: isOutgoing,
            theme: theme,
            loadingFilePreviewIDs: loadingFilePreviewIDs
        )
        metadataView.configure(
            message: message,
            tintColor: MessageBubbleStyle.secondaryColor(
                isOutgoing: isOutgoing,
                theme: theme
            ),
            timestampAccessibilityIdentifier: "fileMessageMetadataLabel",
            statusAccessibilityIdentifier: "fileMessageStatusImageView"
        )
    }

    /// Refreshes only the outgoing delivery status without rebuilding file rows.
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
            statusAccessibilityIdentifier: "fileMessageStatusImageView"
        )
    }

    private func configureBubble(
        isOutgoing: Bool,
        roundsAllCorners: Bool,
        theme: ConsultantTheme
    ) {
        bubbleView.backgroundColor = MessageBubbleStyle.bubbleColor(
            isOutgoing: isOutgoing,
            theme: theme
        )
        bubbleView.layer.cornerRadius = theme.roundedElements
            ? MessageLayout.contentCornerRadius
            : MessageLayout.compactCornerRadius
        bubbleView.layer.borderWidth = 0
        bubbleView.layer.borderColor = nil
        bubbleView.layer.maskedCorners = roundsAllCorners
            ? Self.allCorners
            : tailCorners(isOutgoing: isOutgoing)
    }

    private func configureColors(
        isOutgoing: Bool,
        theme: ConsultantTheme
    ) {
        let mainColor = theme.brandColor
        let primaryTextColor = MessageBubbleStyle.textColor(
            isOutgoing: isOutgoing,
            theme: theme
        )
        let sizeTextColor = isOutgoing
            ? theme.mainTextColor
            : theme.messageDateColor

        authorLabel.textColor = primaryTextColor
        fileRowViews.forEach {
            $0.configureColors(
                isOutgoing: isOutgoing,
                primaryTextColor: primaryTextColor,
                sizeTextColor: sizeTextColor,
                iconBackgroundColor: isOutgoing
                    ? theme.mainTextColor
                    : mainColor,
                iconTintColor: isOutgoing
                    ? mainColor
                    : theme.mainTextColor
            )
        }
    }

    private func configureFileRows(
        items: [MessageFileDisplayItem],
        previewItems: [FilePreviewItem],
        isOutgoing: Bool,
        theme: ConsultantTheme,
        loadingFilePreviewIDs: Set<String>
    ) {
        removeFileRows()

        var nextPreviewIndex = 0

        for item in items {
            let rowView = FileMessageItemView()
            let previewIndex: Int?
            if item.urlString.flatMap(URL.init(string:)) == nil {
                previewIndex = nil
            } else {
                previewIndex = nextPreviewIndex
                nextPreviewIndex += 1
            }
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowView.onTap = { [weak self] in
                guard let previewIndex else {
                    return
                }

                self?.onFilePreview?(previewItems, previewIndex)
            }
            rowView.configure(
                item: item,
                isTapEnabled: previewIndex != nil,
                isLoading: item.id.map { loadingFilePreviewIDs.contains($0) } ?? false
            )
            filesStackView.addArrangedSubview(rowView)
            fileRowViews.append(rowView)

            rowView.heightAnchor.constraint(
                equalToConstant: FileMessageLayout.fileBlockHeight
            ).isActive = true
        }

        configureColors(
            isOutgoing: isOutgoing,
            theme: theme
        )
    }

    private func removeFileRows() {
        for rowView in fileRowViews {
            rowView.prepareForReuse()
            filesStackView.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        fileRowViews.removeAll()
    }

    private func tailCorners(isOutgoing: Bool) -> CACornerMask {
        isOutgoing
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

}

package extension FileMessageBubbleView {
    /// Calculates the height needed for the current number of file rows.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth _: CGFloat,
        showsAuthor: Bool
    ) -> CGFloat {
        FileMessageLayout.preferredHeight(
            showsAuthor: showsAuthor,
            itemCount: message.fileDisplayItems.count
        )
    }

    private static let allCorners: CACornerMask = [
        .layerMinXMinYCorner,
        .layerMaxXMinYCorner,
        .layerMinXMaxYCorner,
        .layerMaxXMaxYCorner
    ]
}
