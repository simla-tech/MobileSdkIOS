import UIKit

/// Renders a product message with image, title, price, quantity, author, and metadata.
package final class ProductMessageBubbleView: UIView {

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView(
            contentInsets: UIEdgeInsets(
                top: MessageLayout.bubbleVerticalInset,
                left: MessageLayout.bubbleHorizontalInset,
                bottom: MessageLayout.bubbleVerticalInset,
                right: MessageLayout.bubbleHorizontalInset
            )
        )
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
        label.accessibilityIdentifier = "productMessageAuthorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let textStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = MessageLayout.bubbleContentSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var textTrailingConstraint: NSLayoutConstraint?

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.messageFont
        label.numberOfLines = Int(ProductMessageLayout.titleMaxLines)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "productMessageTitleLabel"
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProductURL)))
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var infoStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var priceLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.semiboldCompactFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "productMessagePriceLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var quantityLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularCompactFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "productMessageQuantityLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var imageRowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var imageContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = MessageBubbleStyle.placeholderBackgroundColor
        view.layer.cornerRadius = MessageLayout.contentCornerRadius
        view.clipsToBounds = true
        view.accessibilityIdentifier = "productMessageImageContainerView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.accessibilityIdentifier = "productMessageImageView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var placeholderImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.photo.image
        view.tintColor = MessageBubbleStyle.placeholderIconColor
        view.contentMode = .scaleAspectFit
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

    private var imageLoadTask: ImageLoadTask?
    private var currentImageURL: URL?
    private var productURL: URL?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Cancels image loading and clears product, author, and metadata state before reuse.
    package func prepareForReuse() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        authorLabel.text = nil
        authorLabel.isHidden = false
        titleLabel.text = nil
        productURL = nil
        titleLabel.isUserInteractionEnabled = false
        titleLabel.accessibilityTraits = .staticText
        priceLabel.text = nil
        quantityLabel.text = nil
        priceLabel.isHidden = false
        quantityLabel.isHidden = false
        infoStackView.isHidden = false
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

        infoStackView.addArrangedSubview(priceLabel)
        infoStackView.addArrangedSubview(quantityLabel)

        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(placeholderImageView)

        contentStackView.addArrangedSubview(authorLabel)
        contentStackView.addArrangedSubview(imageRowView)
        contentStackView.addArrangedSubview(textContentView)
        textContentView.addSubview(textStackView)
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(infoStackView)
        contentStackView.addArrangedSubview(metadataView)

        imageRowView.addSubview(imageContainerView)
    }

    private func setupConstraints() {
        let textTrailingConstraint = textStackView.trailingAnchor.constraint(equalTo: textContentView.trailingAnchor)
        self.textTrailingConstraint = textTrailingConstraint
        NSLayoutConstraint.activate([
            textStackView.topAnchor.constraint(equalTo: textContentView.topAnchor),
            textStackView.bottomAnchor.constraint(equalTo: textContentView.bottomAnchor),
            textStackView.leadingAnchor.constraint(equalTo: textContentView.leadingAnchor),
            textTrailingConstraint,
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),

            imageRowView.heightAnchor.constraint(equalToConstant: ProductMessageLayout.imageSize),

            imageContainerView.topAnchor.constraint(equalTo: imageRowView.topAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: imageRowView.leadingAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: imageRowView.bottomAnchor),
            imageContainerView.widthAnchor.constraint(equalToConstant: ProductMessageLayout.imageSize),

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 32),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 32),

            metadataView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: MessageLayout.secondaryLineHeight
            )
        ])
    }

    /// Applies product display data, author visibility, bubble shape, colors, image loading, and metadata.
    package func configure(
        message: ConsultantMessage,
        showsAuthor: Bool,
        roundsAllCorners: Bool,
        theme: ConsultantTheme = .defaultTheme,
        authorNameOverride: String? = nil,
        imageWorkers: [String] = []
    ) {
        let isOutgoing = message.fromMe == true
        textTrailingConstraint?.constant = -ProductMessageLayout.additionalTextTrailingInset(isOutgoing: isOutgoing)
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

        titleLabel.text = message.productDisplayName
        productURL = message.product?.url
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { $0.scheme?.isEmpty == false ? $0 : nil }
        titleLabel.textColor = productURL == nil ? textColor : theme.brandColor
        titleLabel.isUserInteractionEnabled = productURL != nil
        titleLabel.accessibilityTraits = productURL == nil ? .staticText : .link

        priceLabel.text = message.productPriceLabel
        priceLabel.textColor = textColor
        priceLabel.isHidden = message.productPriceLabel?.isEmpty != false

        quantityLabel.text = message.productQuantityLabel
        quantityLabel.textColor = quantityColor(
            message: message,
            isOutgoing: isOutgoing,
            theme: theme
        )
        quantityLabel.isHidden = message.productQuantityLabel?.isEmpty != false
        infoStackView.isHidden = priceLabel.isHidden && quantityLabel.isHidden

        metadataView.configure(
            message: message,
            tintColor: secondaryColor,
            timestampAccessibilityIdentifier: "productMessageMetadataLabel",
            statusAccessibilityIdentifier: "productMessageStatusImageView"
        )
        loadImage(
            from: ProductImagePreviewURL.make(
                imageURLString: message.product?.img,
                imageWorkers: imageWorkers
            )
        )
    }

    /// Refreshes only the outgoing delivery status without rebuilding product content.
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
            statusAccessibilityIdentifier: "productMessageStatusImageView"
        )
    }

    @objc
    private func openProductURL() {
        guard let productURL else { return }
        UIApplication.shared.open(productURL, options: [:])
    }

    private func loadImage(from url: URL?) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = url
        imageView.image = nil
        placeholderImageView.isHidden = false

        guard let url else {
            return
        }

        imageLoadTask = ImageLoader.shared.loadImage(from: url) { [weak self] image in
            guard self?.currentImageURL == url else {
                return
            }

            self?.imageView.image = image
            self?.placeholderImageView.isHidden = image != nil
        }
    }

    private func quantityColor(
        message: ConsultantMessage,
        isOutgoing: Bool,
        theme: ConsultantTheme
    ) -> UIColor {
        if isOutgoing {
            return theme.mainTextColor
        }

        return message.product?.quantity?.isAvailable == false
            ? MessageBubbleStyle.outOfStockColor
            : MessageBubbleStyle.inStockColor
    }

}

package extension ProductMessageBubbleView {
    /// Calculates the height needed for product content and optional author.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat,
        showsAuthor: Bool
    ) -> CGFloat {
        let maxTitleWidth = max(
            1,
            MessageCollectionViewCell.preferredBubbleWidth(
                for: message, collectionWidth: collectionWidth, showsAuthor: showsAuthor
            ) - MessageLayout.bubbleHorizontalInset * 2
                - ProductMessageLayout.additionalTextTrailingInset(isOutgoing: message.fromMe == true)
        )
        let titleHeight = height(
            for: message.productDisplayName,
            width: maxTitleWidth,
            font: MessageBubbleStyle.messageFont
        )

        return ProductMessageLayout.preferredHeight(
            titleHeight: titleHeight,
            showsAuthor: showsAuthor,
            showsPrice: message.productPriceLabel?.isEmpty == false,
            showsQuantity: message.productQuantityLabel?.isEmpty == false
        )
    }

    private static func height(for text: String, width: CGFloat, font: UIFont) -> CGFloat {
        ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
        )
    }

}
