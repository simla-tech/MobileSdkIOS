//
//  OrderItemLinkView.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 21.07.2026.
//

import UIKit

/// Renders a tappable order item title as a plain text link without underline.
package final class OrderItemLinkView: UIControl {

    /// URL opened when the containing order bubble receives this control tap.
    package var url: URL?

    private let titleLabel = UILabel()
    private var linkRange = NSRange(location: 0, length: 0)

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    package override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.62 : 1
        }
    }

    /// Applies link title, URL, color, and accessibility label.
    package func configure(
        title: String,
        prefix: String,
        url: URL,
        textColor: UIColor,
        linkColor: UIColor
    ) {
        self.url = url
        let text = NSMutableAttributedString(
            string: prefix + title,
            attributes: [
                .font: MessageBubbleStyle.messageFont,
                .foregroundColor: textColor
            ]
        )
        linkRange = NSRange(location: (prefix as NSString).length, length: (title as NSString).length)
        text.addAttribute(.foregroundColor, value: linkColor, range: linkRange)
        titleLabel.attributedText = text
        accessibilityLabel = title
    }

    /// Only the product name is interactive; the list number and empty space are plain text.
    package override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event),
              let text = titleLabel.attributedText, linkRange.length > 0 else {
            return false
        }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: titleLabel.bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = titleLabel.numberOfLines
        container.lineBreakMode = titleLabel.lineBreakMode
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let textRect = titleLabel.textRect(forBounds: titleLabel.bounds, limitedToNumberOfLines: titleLabel.numberOfLines)
        let labelPoint = titleLabel.convert(point, from: self)
        let textOriginY = (titleLabel.bounds.height - textRect.height) / 2
        let textPoint = CGPoint(x: labelPoint.x - textRect.minX, y: labelPoint.y - textOriginY)
        let glyph = manager.glyphIndex(for: textPoint, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(textPoint) else {
            return false
        }
        return NSLocationInRange(manager.characterIndexForGlyph(at: glyph), linkRange)
    }

    private func setup() {
        isAccessibilityElement = true
        accessibilityTraits = .link

        titleLabel.font = MessageBubbleStyle.messageFont
        titleLabel.numberOfLines = Int(OrderMessageLayout.itemNameMaxLines)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
