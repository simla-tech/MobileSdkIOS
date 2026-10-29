import UIKit

/// Renders an attachment selected in the message input before it is sent.
package final class InputAttachmentCollectionViewCell: UICollectionViewCell {

    private enum Constants {
        static let cornerRadius: CGFloat = 10
        static let removeButtonSize: CGFloat = 24
        static let overlayColor = UIColor.black.withAlphaComponent(0.48)
        static let secondaryColor = UIColor(red: 0.39, green: 0.44, blue: 0.50, alpha: 1.0)
    }

    private lazy var previewContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.secondaryColor.withAlphaComponent(0.08)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fileIconImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.document.image
        view.tintColor = Constants.secondaryColor.withAlphaComponent(0.72)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fileExtensionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = Constants.secondaryColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var fileNameBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.overlayColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fileNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        return label
    }()

    private lazy var statusOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.overlayColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var statusStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var activityIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var statusImageView: UIImageView = {
        let view = UIImageView()
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        button.tintColor = .white
        button.layer.cornerRadius = Constants.removeButtonSize / 2
        button.setImage(ConsultantImageResource.arrowClockwise.image, for: .normal)
        button.accessibilityIdentifier = "retryInputAttachmentButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(ConsultantImageResource.close.image, for: .normal)
        button.accessibilityIdentifier = "removeInputAttachmentButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        return button
    }()

    /// Called when the user taps the remove button for this pending attachment.
    package var onRemove: (() -> Void)?
    /// Called when the user taps retry after an attachment upload failure.
    package var onRetry: (() -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Clears preview, status, and callbacks before the collection view reuses the cell.
    package override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        fileExtensionLabel.text = nil
        fileNameLabel.text = nil
        activityIndicatorView.stopAnimating()
        statusImageView.image = nil
        statusLabel.text = nil
        onRemove = nil
        onRetry = nil
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = Constants.cornerRadius
        contentView.layer.borderColor = Constants.secondaryColor.withAlphaComponent(0.18).cgColor
        contentView.layer.borderWidth = 0.5
        contentView.clipsToBounds = true

        contentView.addSubview(previewContainerView)
        contentView.addSubview(fileNameBackgroundView)
        fileNameBackgroundView.addSubview(fileNameLabel)
        contentView.addSubview(statusOverlayView)
        contentView.addSubview(removeButton)

        previewContainerView.addSubview(imageView)
        previewContainerView.addSubview(fileIconImageView)
        previewContainerView.addSubview(fileExtensionLabel)

        statusOverlayView.addSubview(statusStackView)

        statusStackView.addArrangedSubview(activityIndicatorView)
        statusStackView.addArrangedSubview(statusImageView)
        statusStackView.addArrangedSubview(statusLabel)
        statusStackView.addArrangedSubview(retryButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            previewContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

            fileIconImageView.centerXAnchor.constraint(equalTo: previewContainerView.centerXAnchor),
            fileIconImageView.centerYAnchor.constraint(equalTo: previewContainerView.centerYAnchor, constant: -18),
            fileIconImageView.widthAnchor.constraint(equalToConstant: 26),
            fileIconImageView.heightAnchor.constraint(equalToConstant: 30),

            fileExtensionLabel.topAnchor.constraint(equalTo: fileIconImageView.bottomAnchor, constant: -2),
            fileExtensionLabel.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 8),
            fileExtensionLabel.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -8),

            fileNameBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fileNameBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            fileNameBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            fileNameLabel.topAnchor.constraint(equalTo: fileNameBackgroundView.topAnchor, constant: 4),
            fileNameLabel.leadingAnchor.constraint(equalTo: fileNameBackgroundView.leadingAnchor, constant: 4),
            fileNameLabel.trailingAnchor.constraint(equalTo: fileNameBackgroundView.trailingAnchor, constant: -4),
            fileNameLabel.bottomAnchor.constraint(equalTo: fileNameBackgroundView.bottomAnchor, constant: -4),

            statusOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            statusOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            statusStackView.centerXAnchor.constraint(equalTo: statusOverlayView.centerXAnchor),
            statusStackView.centerYAnchor.constraint(equalTo: statusOverlayView.centerYAnchor),
            statusStackView.leadingAnchor.constraint(greaterThanOrEqualTo: statusOverlayView.leadingAnchor, constant: 6),
            statusStackView.trailingAnchor.constraint(lessThanOrEqualTo: statusOverlayView.trailingAnchor, constant: -6),

            retryButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            retryButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),

            removeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize)
        ])
    }

    /// Applies file preview, visible file name, upload status, and accessibility label.
    package func configure(_ attachment: InputAttachment) {
        fileNameLabel.text = attachment.fileName
        configurePreview(attachment)
        configureStatus(attachment.status)
        accessibilityLabel = attachment.fileName
    }

    private func configurePreview(_ attachment: InputAttachment) {
        let image = attachment.previewData.flatMap(UIImage.init(data:))
        let isImage = attachment.messageType == "image" || attachment.contentType.hasPrefix("image/")

        imageView.image = isImage ? image : nil
        imageView.isHidden = imageView.image == nil
        fileIconImageView.isHidden = !imageView.isHidden
        fileExtensionLabel.isHidden = !imageView.isHidden
        fileExtensionLabel.text = fileExtension(from: attachment.fileName)
    }

    private func configureStatus(_ status: InputAttachmentStatus) {
        activityIndicatorView.isHidden = true
        statusImageView.isHidden = true
        retryButton.isHidden = true
        statusOverlayView.isHidden = false

        switch status {
        case .uploading:
            activityIndicatorView.isHidden = false
            activityIndicatorView.startAnimating()
            statusLabel.text = ConsultantLocalization.attachmentStatusLoading.localized
        case .uploaded:
            statusOverlayView.isHidden = true
            statusLabel.text = nil
        case .failed:
            statusImageView.isHidden = false
            statusImageView.image = ConsultantImageResource.errorTriangle.image
            statusLabel.text = ConsultantLocalization.commonError.localized
            retryButton.isHidden = false
        }
    }

    private func fileExtension(from fileName: String) -> String {
        let pathExtension = (fileName as NSString).pathExtension

        guard !pathExtension.isEmpty else {
            return ConsultantLocalization.attachmentFileExtensionFallback.localized
        }

        return pathExtension.uppercased()
    }

    @objc private func removeButtonTapped() {
        onRemove?()
    }

    @objc private func retryButtonTapped() {
        onRetry?()
    }
}
