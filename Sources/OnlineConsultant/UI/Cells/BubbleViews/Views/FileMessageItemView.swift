//
//  OnlineConsultantFileMessageRowView.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 21.07.2026.
//

import UIKit

/// Renders a single file attachment row inside a file message bubble.
package final class FileMessageItemView: UIView {

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = MessageLayout.contentCornerRadius
        view.clipsToBounds = true
        view.accessibilityIdentifier = "fileMessageIconContainerView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.paperclip.templateImage
        view.contentMode = .scaleAspectFit
        view.accessibilityIdentifier = "fileMessageIconImageView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var loadingIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.hidesWhenStopped = true
        view.accessibilityIdentifier = "fileMessageLoadingIndicator"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.semiboldMediumFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        label.accessibilityIdentifier = "fileMessageTitleLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var sizeLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularSmallFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "fileMessageSizeLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var tapButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityIdentifier = "fileMessageTapButton"
        button.addTarget(
            self,
            action: #selector(handleTap),
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    /// Called when the row is tapped and file preview is enabled.
    package var onTap: (() -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Clears file labels, loading state, tap state, and callback before reuse.
    package func prepareForReuse() {
        titleLabel.text = nil
        sizeLabel.text = nil
        sizeLabel.isHidden = false
        tapButton.isEnabled = false
        tapButton.isHidden = true
        setLoading(false)
        onTap = nil
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        accessibilityIdentifier = "fileMessageRowView"

        addSubview(iconContainerView)

        iconContainerView.addSubview(iconImageView)
        iconContainerView.addSubview(loadingIndicatorView)

        addSubview(textStackView)

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(sizeLabel)

        addSubview(tapButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconContainerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: FileMessageLayout.fileIconSize),
            iconContainerView.heightAnchor.constraint(equalToConstant: FileMessageLayout.fileIconSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            loadingIndicatorView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            loadingIndicatorView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),

            textStackView.leadingAnchor.constraint(
                equalTo: iconContainerView.trailingAnchor,
                constant: MessageLayout.contentItemSpacing
            ),
            textStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStackView.heightAnchor.constraint(
                equalToConstant: MessageLayout.contentLineHeight
                    + MessageLayout.secondaryLineHeight
            ),

            titleLabel.heightAnchor.constraint(equalToConstant: MessageLayout.contentLineHeight),
            sizeLabel.heightAnchor.constraint(equalToConstant: MessageLayout.secondaryLineHeight),

            tapButton.topAnchor.constraint(equalTo: topAnchor),
            tapButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            tapButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Applies file title, size, preview availability, and loading state.
    package func configure(
        item: MessageFileDisplayItem,
        isTapEnabled: Bool,
        isLoading: Bool = false
    ) {
        titleLabel.text = item.displayName
        sizeLabel.text = item.sizeLabel
        sizeLabel.isHidden = item.sizeLabel?.isEmpty != false
        tapButton.isEnabled = isTapEnabled
        tapButton.isHidden = !isTapEnabled
        setLoading(isLoading)
    }

    /// Applies row colors derived from the containing incoming or outgoing bubble.
    package func configureColors(
        isOutgoing _: Bool,
        primaryTextColor: UIColor,
        sizeTextColor: UIColor,
        iconBackgroundColor: UIColor,
        iconTintColor: UIColor
    ) {
        titleLabel.textColor = primaryTextColor
        sizeLabel.textColor = sizeTextColor
        iconContainerView.backgroundColor = iconBackgroundColor
        iconImageView.tintColor = iconTintColor
        loadingIndicatorView.color = iconTintColor
    }

    @objc private func handleTap() {
        onTap?()
    }

    private func setLoading(_ isLoading: Bool) {
        if isLoading {
            loadingIndicatorView.startAnimating()
        } else {
            loadingIndicatorView.stopAnimating()
        }
    }
}
