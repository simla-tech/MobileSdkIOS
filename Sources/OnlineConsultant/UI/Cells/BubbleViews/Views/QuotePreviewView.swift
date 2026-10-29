//
//  QuotePreviewView.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 21.07.2026.
//

import UIKit

/// Renders text, files, and image thumbnails inside a quote message bubble.
package final class QuotePreviewView: UIView {

    private let barView: UIView = {
        let view = UIView()
        view.backgroundColor = MessageBubbleStyle.quoteBarColor
        view.layer.cornerRadius = 1
        view.clipsToBounds = true
        view.accessibilityIdentifier = "quotePreviewBarView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var imageLoadTasks: [ImageLoadTask] = []
    private var configurationID = UUID()

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Cancels thumbnail loading and clears content before reuse or reconfiguration.
    package func prepareForReuse() {
        configurationID = UUID()
        imageLoadTasks.forEach { $0.cancel() }
        imageLoadTasks.removeAll()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    deinit {
        imageLoadTasks.forEach { $0.cancel() }
    }

    package func configure(preview: MessageQuotePreview, textColor: UIColor = MessageBubbleStyle.textColor) {
        prepareForReuse()
        switch preview {
        case .text(let text):
            barView.backgroundColor = MessageBubbleStyle.quoteBarColor
            addText(text)
        case .attachments(let items, let isImage, let text, let author):
            barView.backgroundColor = UIColor(red: 99 / 255, green: 111 / 255, blue: 127 / 255, alpha: 0.47)
            for item in items {
                addAttachment(item, isImage: isImage, author: author, textColor: textColor)
            }
            if let text { addText(text) }
        }
    }

    private func setup() {
        accessibilityIdentifier = "quotePreviewView"
        addSubview(barView)
        addSubview(contentStackView)
        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: leadingAnchor),
            barView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            barView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            barView.widthAnchor.constraint(equalToConstant: QuoteMessageLayout.quoteBarWidth),
            contentStackView.leadingAnchor.constraint(
                equalTo: barView.trailingAnchor,
                constant: QuoteMessageLayout.quoteBarContentSpacing
            ),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeLabel(_ text: String, identifier: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = MessageBubbleStyle.regularSmallFont
        label.textColor = MessageBubbleStyle.quoteTextColor
        label.lineBreakMode = .byTruncatingMiddle
        label.accessibilityIdentifier = identifier
        return label
    }

    private func addText(_ text: String) {
        let label = makeLabel(text, identifier: "quotePreviewPrimaryLabel")
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        let row = UIStackView(arrangedSubviews: [label])
        row.alignment = .center
        row.heightAnchor.constraint(equalToConstant: QuoteMessageLayout.quoteTextMinHeight).isActive = true
        contentStackView.addArrangedSubview(row)
    }

    private func addAttachment(_ item: MessageItem, isImage: Bool, author: String, textColor: UIColor) {
        let title = makeLabel(
            isImage ? ConsultantLocalization.messageQuotePhoto.localized
                : item.caption ?? ConsultantLocalization.commonFile.localized,
            identifier: "quotePreviewAttachmentTitleLabel"
        )
        title.textColor = textColor
        let authorLabel = makeLabel(author, identifier: "quotePreviewAuthorLabel")
        authorLabel.font = MessageBubbleStyle.authorFont
        authorLabel.textColor = textColor
        let labels = UIStackView(arrangedSubviews: [authorLabel, title])
        labels.axis = .vertical
        authorLabel.heightAnchor.constraint(equalToConstant: QuoteMessageLayout.authorHeight).isActive = true
        title.heightAnchor.constraint(equalToConstant: MessageLayout.secondaryLineHeight).isActive = true
        let row = UIStackView()
        row.alignment = .center
        row.spacing = QuoteMessageLayout.thumbnailSpacing
        row.heightAnchor.constraint(
            equalToConstant: QuoteMessageLayout.attachmentRowHeight(isImage: isImage)
        ).isActive = true
        let iconContainer = UIView()
        iconContainer.backgroundColor = MessageBubbleStyle.placeholderBackgroundColor
        iconContainer.layer.cornerRadius = 4
        iconContainer.clipsToBounds = true
        row.addArrangedSubview(iconContainer)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: QuoteMessageLayout.thumbnailSize),
            iconContainer.heightAnchor.constraint(equalToConstant: QuoteMessageLayout.thumbnailSize)
        ])
        let thumbnail = UIImageView(image: isImage
            ? ConsultantImageResource.photo.image
            : ConsultantImageResource.paperclip.templateImage)
        thumbnail.tintColor = MessageBubbleStyle.placeholderIconColor
        thumbnail.contentMode = isImage ? .scaleAspectFill : .scaleAspectFit
        thumbnail.clipsToBounds = true
        thumbnail.accessibilityIdentifier = isImage ? "quotePreviewImageView" : "quotePreviewFileIconView"
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(thumbnail)
        let iconInset: CGFloat = isImage ? 0 : 9
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: iconInset),
            thumbnail.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor, constant: iconInset),
            thumbnail.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: -iconInset),
            thumbnail.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: -iconInset)
        ])
        if isImage {
            if let urlString = item.resolvedFileURL, let url = URL(string: urlString) {
                let id = configurationID
                let task = ImageLoader.shared.loadImage(from: url) { [weak self, weak thumbnail] image in
                    guard self?.configurationID == id, let image else { return }
                    thumbnail?.image = image
                }
                if let task { imageLoadTasks.append(task) }
            }
        }
        row.addArrangedSubview(labels)
        contentStackView.addArrangedSubview(row)
    }
}
