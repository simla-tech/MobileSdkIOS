import UIKit

/// Renders an order message with order number, items, fields, author, and metadata.
package final class OrderMessageBubbleView: UIView {

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView(
            contentInsets: UIEdgeInsets(
                top: MessageLayout.bubbleVerticalInset,
                left: MessageLayout.bubbleHorizontalInset,
                bottom: MessageLayout.bubbleVerticalInset,
                right: MessageLayout.bubbleHorizontalInset
            )
        )
        view.accessibilityIdentifier = "orderMessageBubbleView"
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
        label.accessibilityIdentifier = "orderMessageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var orderNumberLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.semiboldMediumFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "orderMessageNumberLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var orderContentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = MessageLayout.bubbleContentSpacing
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

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Clears order content, author, order number, and metadata before reuse.
    package func prepareForReuse() {
        authorLabel.text = nil
        authorLabel.isHidden = false
        orderNumberLabel.text = nil
        orderNumberLabel.isHidden = false
        clearOrderContent()
        metadataView.prepareForReuse()
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
        contentStackView.addArrangedSubview(orderNumberLabel)
        contentStackView.addArrangedSubview(orderContentStackView)
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

            metadataView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: MessageLayout.secondaryLineHeight
            )
        ])
    }

    /// Applies order display fields, linked items, author visibility, bubble shape, colors, and metadata.
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

        orderNumberLabel.text = message.orderNumberLabel
        orderNumberLabel.textColor = textColor
        orderNumberLabel.isHidden = message.orderNumberLabel?.isEmpty != false

        rebuildOrderContent(
            message: message,
            textColor: textColor,
            linkColor: theme.brandColor,
            secondaryColor: secondaryColor
        )

        metadataView.configure(
            message: message,
            tintColor: secondaryColor,
            timestampAccessibilityIdentifier: "orderMessageMetadataLabel",
            statusAccessibilityIdentifier: "orderMessageStatusImageView"
        )
    }

    /// Refreshes only the outgoing delivery status without rebuilding order content.
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
            statusAccessibilityIdentifier: "orderMessageStatusImageView"
        )
    }

    private func rebuildOrderContent(
        message: ConsultantMessage,
        textColor: UIColor,
        linkColor: UIColor,
        secondaryColor: UIColor
    ) {
        clearOrderContent()

        message.orderDisplayItems.forEach { item in
            orderContentStackView.addArrangedSubview(
                makeOrderItemView(
                    item: item,
                    textColor: textColor,
                    linkColor: linkColor,
                    secondaryColor: secondaryColor
                )
            )
        }

        message.orderDisplayFields.forEach { field in
            orderContentStackView.addArrangedSubview(
                makeFieldView(
                    field: field,
                    textColor: textColor,
                    secondaryColor: secondaryColor
                )
            )
        }

        orderContentStackView.isHidden = orderContentStackView.arrangedSubviews.isEmpty
    }

    private func makeOrderItemView(
        item: MessageOrderDisplayItem,
        textColor: UIColor,
        linkColor: UIColor,
        secondaryColor: UIColor
    ) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = OrderMessageLayout.innerSpacing

        let nameView = makeOrderItemNameView(
            item: item,
            textColor: textColor,
            linkColor: linkColor
        )

        let detailsLabel = UILabel()
        detailsLabel.font = MessageBubbleStyle.regularCompactFont
        detailsLabel.textColor = textColor
        detailsLabel.numberOfLines = 1
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.text = item.details
        detailsLabel.isHidden = item.details.isEmpty
        detailsLabel.accessibilityIdentifier = "orderMessageItemDetailsLabel"

        [nameView, detailsLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview($0)
        }

        return stackView
    }

    private func makeOrderItemNameView(
        item: MessageOrderDisplayItem,
        textColor: UIColor,
        linkColor: UIColor
    ) -> UIView {
        let title = "\(item.numberLabel) \(item.name)"

        guard let url = item.url else {
            let label = UILabel()
            label.font = MessageBubbleStyle.messageFont
            label.textColor = textColor
            label.numberOfLines = Int(OrderMessageLayout.itemNameMaxLines)
            label.lineBreakMode = .byTruncatingTail
            label.text = title
            label.accessibilityIdentifier = "orderMessageItemNameLabel"

            return label
        }

        let linkView = OrderItemLinkView()
        linkView.configure(
            title: item.name,
            prefix: "\(item.numberLabel) ",
            url: url,
            textColor: textColor,
            linkColor: linkColor
        )
        linkView.accessibilityIdentifier = "orderMessageItemNameButton"
        linkView.addTarget(self, action: #selector(openOrderItemURL(_:)), for: .touchUpInside)

        return linkView
    }

    @objc
    private func openOrderItemURL(_ sender: OrderItemLinkView) {
        guard let url = sender.url, url.scheme?.isEmpty == false else {
            return
        }

        UIApplication.shared.open(url, options: [:])
    }

    private func makeFieldView(
        field: MessageOrderDisplayField,
        textColor: UIColor,
        secondaryColor: UIColor
    ) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = OrderMessageLayout.innerSpacing

        let titleLabel = UILabel()
        titleLabel.font = MessageBubbleStyle.semiboldMediumFont
        titleLabel.textColor = textColor
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = field.title
        titleLabel.accessibilityIdentifier = "orderMessageFieldTitleLabel"

        let valueLabel = UILabel()
        valueLabel.font = MessageBubbleStyle.regularCompactFont
        valueLabel.textColor = secondaryColor
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.text = field.value
        valueLabel.accessibilityIdentifier = "orderMessageFieldValueLabel"

        [titleLabel, valueLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview($0)
        }

        return stackView
    }

    private func clearOrderContent() {
        orderContentStackView.arrangedSubviews.forEach { view in
            orderContentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        orderContentStackView.isHidden = false
    }

}

package extension OrderMessageBubbleView {
    /// Calculates the height needed for the order number, order items, fields, and optional author.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool
    ) -> CGFloat {
        let maxContentWidth = max(
            1,
            MessageCollectionViewCell.preferredBubbleWidth(
                for: message, collectionWidth: collectionWidth, showsAuthor: showsAuthor
            ) - MessageLayout.bubbleHorizontalInset * 2
        )
        let orderNumberHeight = message.orderNumberLabel?.isEmpty == false
            ? height(
                for: message.orderNumberLabel,
                width: maxContentWidth,
                font: MessageBubbleStyle.semiboldMediumFont,
                maxLines: 1
            )
            : 0
        let itemHeights = message.orderDisplayItems.map {
            itemHeight(
                item: $0,
                width: maxContentWidth
            )
        }
        let fieldHeights = message.orderDisplayFields.map {
            fieldHeight(
                field: $0,
                width: maxContentWidth
            )
        }

        return OrderMessageLayout.preferredHeight(
            orderNumberHeight: orderNumberHeight,
            itemHeights: itemHeights,
            fieldHeights: fieldHeights,
            showsAuthor: showsAuthor
        )
    }

    private static func itemHeight(
        item: MessageOrderDisplayItem,
        width: CGFloat
    ) -> CGFloat {
        let nameHeight = height(
            for: "\(item.numberLabel) \(item.name)",
            width: width,
            font: MessageBubbleStyle.messageFont,
            maxLines: Int(OrderMessageLayout.itemNameMaxLines)
        )
        let detailsHeight = item.details.isEmpty
            ? 0
            : height(
                for: item.details,
                width: width,
                font: MessageBubbleStyle.regularCompactFont,
                maxLines: 1
            )
        let spacing = detailsHeight > 0 ? OrderMessageLayout.innerSpacing : 0

        return ceil(
            nameHeight
                + spacing
                + detailsHeight
        )
    }

    private static func fieldHeight(
        field: MessageOrderDisplayField,
        width: CGFloat
    ) -> CGFloat {
        let titleHeight = height(
            for: field.title,
            width: width,
            font: MessageBubbleStyle.semiboldMediumFont,
            maxLines: 1
        )
        let valueHeight = height(
            for: field.value,
            width: width,
            font: MessageBubbleStyle.regularCompactFont,
            maxLines: 0
        )

        return ceil(
            titleHeight
                + OrderMessageLayout.innerSpacing
                + valueHeight
        )
    }

    private static func height(
        for text: String?,
        width: CGFloat,
        font: UIFont,
        maxLines: Int
    ) -> CGFloat {
        guard let text, !text.isEmpty else {
            return 0
        }

        let measured = ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
        )

        guard maxLines > 0 else {
            return measured
        }

        return min(measured, ceil(font.lineHeight * CGFloat(maxLines)))
    }
}
