import UIKit

/// Displays the personal data processing agreement notice above the input bar.
package final class AgreementView: UIView {

    package static let height: CGFloat = 47
    package static let horizontalInset: CGFloat = 16
    private static let itemSpacing: CGFloat = 8
    private static let iconSize: CGFloat = 24
    package static let backgroundColor = UIColor(hex: 0x636F7F, alpha: 0.20)
    private static let initialIconColor = UIColor(hex: 0x005EEB)
    package static let linkColor = UIColor(hex: 0x0052CC)

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularCompactFont
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.accessibilityIdentifier = "agreementLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var iconImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.infoIcon.templateImage
        view.tintColor = Self.initialIconColor
        view.contentMode = .scaleAspectFit
        view.accessibilityIdentifier = "agreementIcon"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var heightConstraint: NSLayoutConstraint?
    private var link: URL?

    /// Called when the user taps the agreement notice with an available link.
    package var onTap: ((URL) -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Self.backgroundColor
        accessibilityIdentifier = "agreementView"
        isUserInteractionEnabled = true

        setupSubviews()
        setupConstraints()
        setupGesture()
    }

    private func setupSubviews() {
        addSubview(textLabel)
        addSubview(iconImageView)
    }

    private func setupConstraints() {
        let heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            heightConstraint,
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            textLabel.leadingAnchor.constraint(
                equalTo: iconImageView.trailingAnchor,
                constant: Self.itemSpacing
            ),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset)
        ])
    }

    private func setupGesture() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    /// Applies theme colors and shows the agreement only when a link is available.
    package func configure(theme: ConsultantTheme, link: URL?) {
        self.link = link
        let isVisible = link != nil
        isHidden = !isVisible
        heightConstraint?.constant = isVisible ? Self.height : 0
        iconImageView.tintColor = Self.linkColor
        textLabel.attributedText = Self.makeText(
            textColor: theme.primaryTextColor,
            linkColor: Self.linkColor
        )
    }

    @objc
    private func handleTap() {
        guard let link else {
            return
        }

        onTap?(link)
    }
}

private extension AgreementView {

    static func makeText(textColor: UIColor, linkColor: UIColor) -> NSAttributedString {
        let firstPart = ConsultantLocalization.messageAgreementFirst.localized
        let linkPart = ConsultantLocalization.messageAgreementLink.localized
        let thirdPart = ConsultantLocalization.messageAgreementThird.localized
        let text = firstPart + linkPart + thirdPart
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: textColor,
                .font: MessageBubbleStyle.regularCompactFont
            ]
        )
        let linkRange = (text as NSString).range(of: linkPart)
        if linkRange.location != NSNotFound {
            attributedText.addAttributes(
                [
                    .foregroundColor: linkColor
                ],
                range: linkRange
            )
        }
        return attributedText
    }
}
