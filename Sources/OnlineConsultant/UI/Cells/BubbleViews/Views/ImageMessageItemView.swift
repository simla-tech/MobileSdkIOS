//
//  ImageMessageItemView.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 21.07.2026.
//

import UIKit

/// Renders a single image attachment inside an image message bubble.
package final class ImageMessageItemView: UIView {

    private lazy var imageContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = MessageBubbleStyle.placeholderBackgroundColor
        view.layer.cornerRadius = MessageLayout.contentCornerRadius
        view.clipsToBounds = true
        view.accessibilityIdentifier = "imageMessageImageContainerView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.accessibilityIdentifier = "imageMessageImageView"
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

    private lazy var metadataOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 13 / 255, green: 15 / 255, blue: 31 / 255, alpha: 0.4)
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var metadataView: MetadataView = {
        let view = MetadataView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var loadingOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0, alpha: 0.28)
        view.isHidden = true
        view.accessibilityIdentifier = "imageMessageLoadingOverlayView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var loadingIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.hidesWhenStopped = true
        view.color = .white
        view.accessibilityIdentifier = "imageMessageLoadingIndicator"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.tintColor = .white
        button.setImage(ConsultantImageResource.arrowClockwise.templateImage, for: .normal)
        button.isHidden = true
        button.accessibilityIdentifier = "imageMessageRetryButton"
        button.addTarget(self, action: #selector(handleRetryTap), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var tapButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityIdentifier = "imageMessageTapButton"
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var imageLoadTask: ImageLoadTask?
    private var currentImageURL: URL?
    private var sourceImageSize: CGSize?
    private var isPreviewTapEnabled = false
    private var isThumbnailLoading = false
    private var isPreviewLoading = false
    private var hasImageLoadError = false
    /// Called when the image is tapped and preview is enabled.
    package var onTap: (() -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Cancels image loading and clears image, metadata, loading, and tap state before reuse.
    package func prepareForReuse() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = nil
        sourceImageSize = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        metadataView.prepareForReuse()
        metadataOverlayView.isHidden = true
        isPreviewTapEnabled = false
        isThumbnailLoading = false
        isPreviewLoading = false
        hasImageLoadError = false
        updateLoadingState()
        updateImageInteractionState()
        tapButton.isEnabled = false
        tapButton.isHidden = true
        onTap = nil
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        addSubview(imageContainerView)

        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(placeholderImageView)
        imageContainerView.addSubview(metadataOverlayView)
        imageContainerView.addSubview(loadingOverlayView)
        imageContainerView.addSubview(tapButton)
        imageContainerView.addSubview(retryButton)

        metadataOverlayView.addSubview(metadataView)

        loadingOverlayView.addSubview(loadingIndicatorView)
    }

    private func setupConstraints() {
        let widthConstraint = imageContainerView.widthAnchor.constraint(
            equalToConstant: ImageMessageLayout.contentWidth
        )
        let heightConstraint = imageContainerView.heightAnchor.constraint(
            equalToConstant: ImageMessageLayout.contentHeight
        )

        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            imageContainerView.topAnchor.constraint(equalTo: topAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
            heightConstraint,

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 36),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 36),

            metadataOverlayView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -4),
            metadataOverlayView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor, constant: -4),
            metadataOverlayView.heightAnchor.constraint(
                equalToConstant: MessageLayout.secondaryLineHeight
            ),

            loadingOverlayView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            loadingOverlayView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            loadingOverlayView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            loadingOverlayView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            loadingIndicatorView.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            loadingIndicatorView.centerYAnchor.constraint(equalTo: loadingOverlayView.centerYAnchor),

            tapButton.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            tapButton.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            tapButton.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            retryButton.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 36),
            retryButton.heightAnchor.constraint(equalToConstant: 36),

            metadataView.topAnchor.constraint(equalTo: metadataOverlayView.topAnchor),
            metadataView.leadingAnchor.constraint(
                equalTo: metadataOverlayView.leadingAnchor,
                constant: ImageMessageLayout.metaOverlayHorizontalInset
            ),
            metadataView.trailingAnchor.constraint(
                equalTo: metadataOverlayView.trailingAnchor,
                constant: -ImageMessageLayout.metaOverlayHorizontalInset
            ),
            metadataView.bottomAnchor.constraint(equalTo: metadataOverlayView.bottomAnchor)
        ])
    }

    /// Applies image source, metadata visibility, preview tap state, loading state, and image worker hosts.
    package func configure(
        item: MessageFileDisplayItem,
        message: ConsultantMessage,
        showsMetadata: Bool,
        imageWorkers: [String],
        isTapEnabled: Bool,
        isLoading: Bool
    ) {
        sourceImageSize = item.sourceImageSize
        loadImage(from: Self.displayImageURL(item.urlString, imageWorkers: imageWorkers))
        isPreviewTapEnabled = isTapEnabled
        setPreviewLoading(isLoading)

        if showsMetadata {
            metadataView.configure(
                message: message,
                tintColor: .white,
                timestampAccessibilityIdentifier: "imageMessageMetadataOverlayLabel",
                statusAccessibilityIdentifier: "imageMessageStatusImageView"
            )
            metadataOverlayView.isHidden = metadataView.isHidden
        } else {
            metadataView.prepareForReuse()
            metadataOverlayView.isHidden = true
        }
    }

    /// Refreshes delivery metadata shown in the image overlay.
    package func updateDeliveryStatus(
        message: ConsultantMessage,
        statusAccessibilityIdentifier: String
    ) {
        metadataView.updateDeliveryStatus(
            message: message,
            tintColor: .white,
            statusAccessibilityIdentifier: statusAccessibilityIdentifier
        )
        metadataOverlayView.isHidden = metadataView.isHidden
    }

    /// Updates image dimensions after the containing bubble width is known.
    package func updateSize(maxBubbleWidth: CGFloat) {
        let imageSize = ImageMessageLayout.imageSize(
            maxBubbleWidth: maxBubbleWidth,
            sourceSize: sourceImageSize
        )
        widthConstraint?.constant = imageSize.width
        heightConstraint?.constant = imageSize.height
    }

    private func setThumbnailLoading(_ isLoading: Bool) {
        isThumbnailLoading = isLoading
        updateLoadingState()
        updateImageInteractionState()
    }

    private func setPreviewLoading(_ isLoading: Bool) {
        isPreviewLoading = isLoading
        updateLoadingState()
        updateImageInteractionState()
    }

    private func updateLoadingState() {
        let isLoading = isThumbnailLoading || isPreviewLoading
        loadingOverlayView.isHidden = !isLoading
        if isLoading {
            loadingIndicatorView.startAnimating()
        } else {
            loadingIndicatorView.stopAnimating()
        }
    }

    private func updateImageInteractionState() {
        let canRetry = hasImageLoadError
            && currentImageURL != nil
            && !isThumbnailLoading
            && !isPreviewLoading
        retryButton.isHidden = !canRetry
        tapButton.isEnabled = isPreviewTapEnabled && !canRetry
        tapButton.isHidden = !tapButton.isEnabled
    }

    private func loadImage(from url: URL?) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentImageURL = url
        imageView.image = nil
        placeholderImageView.isHidden = false
        hasImageLoadError = false
        updateImageInteractionState()

        guard let url else {
            setThumbnailLoading(false)
            return
        }

        setThumbnailLoading(true)
        imageLoadTask = ImageLoader.shared.loadImage(from: url) { [weak self] image in
            guard self?.currentImageURL == url else {
                return
            }

            self?.imageLoadTask = nil
            self?.imageView.image = image
            self?.placeholderImageView.isHidden = image != nil
            self?.hasImageLoadError = image == nil
            self?.setThumbnailLoading(false)
        }
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleRetryTap() {
        loadImage(from: currentImageURL)
    }
}

package extension ImageMessageItemView {

    private static func displayImageURL(
        _ urlString: String?,
        imageWorkers: [String]
    ) -> URL? {
        guard let urlString else {
            return nil
        }

        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else {
            return nil
        }

        let url = URL(string: trimmedURLString)
        guard url?.scheme == "http" || url?.scheme == "https" || trimmedURLString.hasPrefix("//") else {
            return url
        }

        return ProductImagePreviewURL.make(
            imageURLString: trimmedURLString,
            imageWorkers: imageWorkers,
            resize: "304x-"
        )
    }
}
