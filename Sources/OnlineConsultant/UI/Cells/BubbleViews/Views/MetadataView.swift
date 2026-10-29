import UIKit

/// Renders message timestamp and outgoing delivery status metadata.
package final class MetadataView: UIView {

    private lazy var stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .horizontal
        view.alignment = .center
        view.distribution = .fill
        view.spacing = MessageLayout.compactSpacing
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.metadataFont
        label.textAlignment = .right
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var statusImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var showsStatusIcon = false

    package override var intrinsicContentSize: CGSize {
        let timestampSize = timestampLabel.isHidden
            ? .zero
            : timestampLabel.intrinsicContentSize
        let statusSize = statusImageView.isHidden
            ? .zero
            : CGSize(
                width: Self.statusIconSize,
                height: Self.statusIconSize
            )
        let spacing = timestampSize.width > 0 && statusSize.width > 0
            ? MessageLayout.compactSpacing
            : 0

        return CGSize(
            width: ceil(timestampSize.width + spacing + statusSize.width),
            height: ceil(max(timestampSize.height, statusSize.height))
        )
    }

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Clears timestamp, status icon, and intrinsic size state before reuse.
    package func prepareForReuse() {
        timestampLabel.text = nil
        timestampLabel.isHidden = false
        statusImageView.image = nil
        statusImageView.isHidden = true
        showsStatusIcon = false
        invalidateIntrinsicContentSize()
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        backgroundColor = .clear

        stackView.addArrangedSubview(timestampLabel)
        stackView.addArrangedSubview(statusImageView)

        addSubview(stackView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusImageView.widthAnchor.constraint(
                equalToConstant: Self.statusIconSize
            ),
            statusImageView.heightAnchor.constraint(
                equalToConstant: Self.statusIconSize
            )
        ])
    }

    /// Applies timestamp and outgoing delivery status for a message.
    package func configure(
        message: ConsultantMessage,
        tintColor: UIColor,
        timestampAccessibilityIdentifier: String,
        statusAccessibilityIdentifier: String
    ) {
        let timestamp = MessageMetadataFormatter.metadataText(for: message)
        let status = message.fromMe == true
            ? MessageDeliveryStatus(messageStatus: message.status)
            : .none

        configure(
            timestamp: timestamp,
            status: status,
            tintColor: tintColor,
            timestampAccessibilityIdentifier: timestampAccessibilityIdentifier,
            statusAccessibilityIdentifier: statusAccessibilityIdentifier
        )
    }

    /// Updates only the outgoing delivery status icon and tint.
    package func updateDeliveryStatus(
        message: ConsultantMessage,
        tintColor: UIColor,
        statusAccessibilityIdentifier: String
    ) {
        let status = message.fromMe == true
            ? MessageDeliveryStatus(messageStatus: message.status)
            : .none

        let image = Self.statusImage(for: status)
        statusImageView.image = image
        statusImageView.tintColor = Self.statusTintColor(
            for: status,
            defaultTintColor: tintColor
        )
        statusImageView.isHidden = image == nil
        statusImageView.accessibilityIdentifier = statusAccessibilityIdentifier
        showsStatusIcon = image != nil

        isHidden = timestampLabel.isHidden && statusImageView.isHidden
        invalidateIntrinsicContentSize()
    }

    private func configure(
        timestamp: String?,
        status: MessageDeliveryStatus,
        tintColor: UIColor,
        timestampAccessibilityIdentifier: String,
        statusAccessibilityIdentifier: String
    ) {
        timestampLabel.text = timestamp
        timestampLabel.textColor = tintColor
        timestampLabel.isHidden = timestamp?.isEmpty != false
        timestampLabel.accessibilityIdentifier = timestampAccessibilityIdentifier

        let image = Self.statusImage(for: status)
        statusImageView.image = image
        statusImageView.tintColor = Self.statusTintColor(
            for: status,
            defaultTintColor: tintColor
        )
        statusImageView.isHidden = image == nil
        statusImageView.accessibilityIdentifier = statusAccessibilityIdentifier
        showsStatusIcon = image != nil

        isHidden = timestampLabel.isHidden && statusImageView.isHidden
        invalidateIntrinsicContentSize()
    }
}

package extension MetadataView {

    private static let statusIconSize: CGFloat = 12

    private static func statusImage(for status: MessageDeliveryStatus) -> UIImage? {
        switch status {
        case .none:
            return nil
        case .sending:
            return ConsultantImageResource.clock.templateImage
        case .delivered:
            return checkmarkImage(count: 1)
        case .read:
            return checkmarkImage(count: 2)
        case .error:
            return ConsultantImageResource.errorCircle.templateImage
        }
    }

    private static func statusTintColor(
        for status: MessageDeliveryStatus,
        defaultTintColor: UIColor
    ) -> UIColor {
        switch status {
        case .error:
            return UIColor(red: 255 / 255, green: 83 / 255, blue: 83 / 255, alpha: 1)
        case .none, .sending, .delivered, .read:
            return defaultTintColor
        }
    }

    private static func checkmarkImage(count: Int) -> UIImage {
        let size = CGSize(
            width: statusIconSize,
            height: statusIconSize
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.black.setStroke()

            for index in 0..<count {
                let offset = count == 1
                    ? 0.75
                    : CGFloat(index) * 3.5
                let path = UIBezierPath()
                path.lineWidth = 1.4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: CGPoint(x: 0.5 + offset, y: 6.4))
                path.addLine(to: CGPoint(x: 3.2 + offset, y: 9.1))
                path.addLine(to: CGPoint(x: 8 + offset, y: 3.4))
                path.stroke()
            }
        }

        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Calculates the metadata width needed for timestamp and optional outgoing status icon.
    static func preferredWidth(for message: ConsultantMessage, maxWidth: CGFloat) -> CGFloat {
        let timestampWidth = width(
            for: MessageMetadataFormatter.metadataText(for: message),
            maxWidth: maxWidth,
            font: MessageBubbleStyle.metadataFont
        )
        let status = message.fromMe == true
            ? MessageDeliveryStatus(messageStatus: message.status)
            : .none
        let statusWidth = status == .none
            ? 0
            : statusIconSize
        let spacing = timestampWidth > 0 && statusWidth > 0
            ? MessageLayout.compactSpacing
            : 0

        return min(maxWidth, ceil(timestampWidth + spacing + statusWidth))
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
}
