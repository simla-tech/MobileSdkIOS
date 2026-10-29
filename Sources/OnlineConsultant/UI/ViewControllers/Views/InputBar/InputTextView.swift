//
//  InputTextView.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import UIKit

/// Text view used by the chat composer with built-in placeholder rendering.
package final class InputTextView: UITextView {

    private let placeholderLabel = UILabel()

    /// Placeholder text shown while the input is empty.
    package var placeholder: String? {
        didSet {
            placeholderLabel.text = placeholder
        }
    }

    /// Placeholder text color applied from the active consultant theme.
    package var placeholderColor: UIColor? {
        didSet {
            placeholderLabel.textColor = placeholderColor
        }
    }

    /// Updates placeholder visibility when text is changed programmatically.
    package override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    /// Updates placeholder visibility when attributed text is changed programmatically.
    package override var attributedText: NSAttributedString! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    /// Keeps the placeholder label visually aligned with the typed text.
    package override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    package override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Positions the placeholder inside the editable text container.
    package override func layoutSubviews() {
        super.layoutSubviews()

        let textContainerInset = self.textContainerInset
        placeholderLabel.frame = CGRect(
            x: textContainerInset.left,
            y: textContainerInset.top,
            width: bounds.width - textContainerInset.left - textContainerInset.right,
            height: placeholderLabel.intrinsicContentSize.height
        )
    }

    private func setup() {
        placeholderLabel.numberOfLines = 1
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = font
        placeholderLabel.isUserInteractionEnabled = false

        addSubview(placeholderLabel)
        updatePlaceholderVisibility()
    }

    /// Shows the placeholder only when the text view has no text.
    package func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
    }
}
