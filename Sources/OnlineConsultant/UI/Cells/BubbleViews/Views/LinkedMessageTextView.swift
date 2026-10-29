import UIKit

/// Displays message text like a label while making plain URLs and emails tappable.
package final class LinkedMessageTextView: UITextView {

    package var onLinkTap: ((URL) -> Void)?

    private var currentLinkTextColor = UIColor.systemBlue

    package override var canBecomeFirstResponder: Bool { false }

    /// Leaves long presses to the bubble's context menu while retaining link taps.
    package override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !(gestureRecognizer is UILongPressGestureRecognizer) else {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    package override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    package func configure(
        text: String?,
        textColor: UIColor,
        font: UIFont,
        linkColor: UIColor = .systemBlue,
        textAlignment: NSTextAlignment = .natural
    ) {
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        currentLinkTextColor = linkColor
        attributedText = Self.attributedText(
            text: text ?? "",
            textColor: textColor,
            font: font,
            linkColor: linkColor
        )
    }

    package func prepareForReuse() {
        text = nil
        attributedText = nil
        onLinkTap = nil
    }

    private func setup() {
        backgroundColor = .clear
        delegate = self
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        setContentCompressionResistancePriority(.required, for: .vertical)
        linkTextAttributes = [
            .foregroundColor: currentLinkTextColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func attributedText(
        text: String,
        textColor: UIColor,
        font: UIFont,
        linkColor: UIColor
    ) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        plainLinks(in: text).forEach { link in
            attributedText.addAttributes(
                [
                    .link: link.url,
                    .foregroundColor: linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: link.range
            )
        }

        return attributedText
    }

    private static func plainLinks(in text: String) -> [(range: NSRange, url: URL)] {
        guard !text.isEmpty else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        return detector?.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard let url = match.url else {
                return nil
            }

            return (match.range, url)
        } ?? []
    }
}

extension LinkedMessageTextView: UITextViewDelegate {

    package func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onLinkTap?(URL)
        return false
    }
}
