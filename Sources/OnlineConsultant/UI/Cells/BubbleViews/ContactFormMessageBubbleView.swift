import UIKit

/// Renders a contact form message with optional title, optional image, and form fields.
package final class ContactFormMessageBubbleView: UIView {

    private lazy var bubbleView: MessageBubbleView = {
        let view = MessageBubbleView(
            contentInsets: UIEdgeInsets(
                top: MessageLayout.bubbleVerticalInset,
                left: MessageLayout.bubbleHorizontalInset,
                bottom: MessageLayout.bubbleVerticalInset,
                right: MessageLayout.bubbleHorizontalInset
            )
        )
        view.accessibilityIdentifier = "contactFormMessageBubbleView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.spacing = MessageLayout.contentItemSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "contactFormTitleLabel"
        label.font = MessageBubbleStyle.semiboldMediumFont
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var imageContainerView: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "contactFormImageContainerView"
        view.backgroundColor = MessageBubbleStyle.placeholderBackgroundColor
        view.layer.cornerRadius = MessageLayout.contentCornerRadius
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.accessibilityIdentifier = "contactFormImageView"
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var placeholderImageView: UIImageView = {
        let view = UIImageView()
        view.accessibilityIdentifier = "contactFormImagePlaceholderView"
        view.image = ConsultantImageResource.photo.image
        view.tintColor = MessageBubbleStyle.placeholderIconColor
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var formContentView: ContactFormContentView = {
        let view = ContactFormContentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var imageHeightConstraint: NSLayoutConstraint?
    private var imageLoadTask: ImageLoadTask?
    private var currentImageURL: URL?
    private var currentImageSize: CGSize?

    /// Called when the embedded contact form passes validation and is submitted.
    package var onSubmit: ((ContactFormSubmitData) -> Void)? {
        didSet {
            formContentView.onSubmit = onSubmit
        }
    }

    package var onPersonalDataLinkTap: ((URL) -> Void)? {
        didSet {
            formContentView.onPersonalDataLinkTap = onPersonalDataLinkTap
        }
    }

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
        updateImageHeight()
    }

    /// Cancels image loading and clears form, title, image, submit callback, and loading state before reuse.
    package func prepareForReuse() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = nil
        currentImageSize = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        titleLabel.text = nil
        titleLabel.isHidden = true
        imageContainerView.isHidden = true
        formContentView.prepareForReuse()
        onSubmit = nil
        onPersonalDataLinkTap = nil
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        backgroundColor = .clear

        addSubview(bubbleView)

        bubbleView.contentView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(titleLabel)

        contentStackView.addArrangedSubview(imageContainerView)

        imageContainerView.addSubview(imageView)

        imageContainerView.addSubview(placeholderImageView)

        contentStackView.addArrangedSubview(formContentView)
    }

    private func setupConstraints() {
        imageHeightConstraint = imageContainerView.heightAnchor.constraint(equalToConstant: 0)
        imageHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 32),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    /// Updates the embedded form submitting state without reconfiguring its fields.
    package func setSubmitting(_ isSubmitting: Bool) {
        formContentView.setSubmitting(isSubmitting)
    }

    /// Applies contact form content, optional header image/title, bubble shape, theme, and submitting state.
    package func configure(
        message: ConsultantMessage,
        roundsAllCorners: Bool,
        isSubmitting: Bool,
        theme: ConsultantTheme = .defaultTheme,
        personalDataLink: URL? = nil
    ) {
        bubbleView.configure(
            isOutgoing: false,
            roundsAllCorners: true,
            theme: theme
        )

        let textColor = MessageBubbleStyle.textColor(
            isOutgoing: false,
            theme: theme
        )
        titleLabel.text = message.header?.nilIfEmpty
        titleLabel.textColor = textColor
        titleLabel.isHidden = titleLabel.text == nil
        loadImage(
            from: message.contactFormImage?.url,
            imageSize: message.contactFormImage?.size
        )

        if let form = message.contactForm {
            formContentView.setTheme(theme)
            formContentView.setPersonalDataLink(personalDataLink)
            formContentView.configure(
                form: form,
                layoutMode: .messageBubble
            )
            formContentView.setSubmitting(isSubmitting)
        }
    }

    private func loadImage(
        from url: URL?,
        imageSize: CGSize?
    ) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = url
        currentImageSize = imageSize
        imageView.image = nil
        placeholderImageView.isHidden = false
        imageContainerView.isHidden = url == nil
        updateImageHeight()

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

    private func updateImageHeight() {
        let width = [
            imageContainerView.bounds.width,
            contentStackView.bounds.width,
            bounds.width - MessageLayout.bubbleHorizontalInset * 2
        ]
        .filter { $0 > 1 }
        .first ?? 1
        imageHeightConstraint?.constant = Self.imageHeight(
            for: currentImageSize,
            url: currentImageURL,
            width: width
        )
    }
}

package extension ContactFormMessageBubbleView {

    /// Calculates the height needed for the form plus optional title and image content.
    static func preferredHeight(
        for message: ConsultantMessage,
        collectionWidth: CGFloat
    ) -> CGFloat {
        guard let form = message.contactForm else {
            return ContactFormMessageLayout.preferredHeight(formHeight: 0)
        }

        let maxBubbleWidth = collectionWidth * MessageLayout.bubbleMaxWidthMultiplier
        let bubbleWidth = ContactFormMessageLayout.preferredBubbleWidth(
            maxBubbleWidth: maxBubbleWidth
        )
        let contentWidth = max(
            1,
            bubbleWidth - MessageLayout.bubbleHorizontalInset * 2
        )
        let formHeight = ContactFormContentView.preferredHeight(
            for: form,
            width: contentWidth,
            layoutMode: .messageBubble
        )
        let titleHeight = Self.titleHeight(
            text: message.header?.nilIfEmpty,
            width: contentWidth
        )
        let imageHeight = Self.imageHeight(
            for: message.contactFormImage?.size,
            url: message.contactFormImage?.url,
            width: contentWidth
        )
        let visibleBlocks = 1
            + (titleHeight > 0 ? 1 : 0)
            + (imageHeight > 0 ? 1 : 0)
        let contentHeight = formHeight
            + titleHeight
            + imageHeight
            + CGFloat(max(0, visibleBlocks - 1)) * MessageLayout.contentItemSpacing

        return ContactFormMessageLayout.preferredHeight(formHeight: contentHeight)
    }

    private static func titleHeight(
        text: String?,
        width: CGFloat
    ) -> CGFloat {
        guard let text else {
            return 0
        }

        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: MessageBubbleStyle.semiboldMediumFont],
                context: nil
            ).height
        )
    }

    private static func imageHeight(
        for imageSize: CGSize?,
        url: URL?,
        width: CGFloat
    ) -> CGFloat {
        guard url != nil else {
            return 0
        }

        guard
            let imageSize,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return MessageLayout.embeddedImageFallbackHeight
        }

        return ceil(width * imageSize.height / imageSize.width)
    }
}
