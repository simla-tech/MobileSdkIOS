import UIKit

/// Provides the shared rounded bubble container used by message-specific bubble views.
package final class MessageBubbleView: UIView {

    /// The inset content container where a message-specific bubble view places its arranged content.
    package private(set) lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var contentInsets: UIEdgeInsets
    private var theme = ConsultantTheme.defaultTheme
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?

    package init(contentInsets: UIEdgeInsets = UIEdgeInsets(
        top: MessageLayout.bubbleVerticalInset,
        left: MessageLayout.bubbleHorizontalInset,
        bottom: MessageLayout.bubbleVerticalInset,
        right: MessageLayout.bubbleHorizontalInset
    )) {
        self.contentInsets = contentInsets
        super.init(frame: .zero)
        setup()
    }

    package override init(frame: CGRect) {
        self.contentInsets = UIEdgeInsets(
            top: MessageLayout.bubbleVerticalInset,
            left: MessageLayout.bubbleHorizontalInset,
            bottom: MessageLayout.bubbleVerticalInset,
            right: MessageLayout.bubbleHorizontalInset
        )
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        self.contentInsets = UIEdgeInsets(
            top: MessageLayout.bubbleVerticalInset,
            left: MessageLayout.bubbleHorizontalInset,
            bottom: MessageLayout.bubbleVerticalInset,
            right: MessageLayout.bubbleHorizontalInset
        )
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        layer.cornerRadius = 12
        clipsToBounds = true

        addSubview(contentView)
    }

    private func setupConstraints() {
        let contentTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top)
        let contentLeadingConstraint = contentView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: contentInsets.left
        )
        let contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -contentInsets.right
        )
        let contentBottomConstraint = contentView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -contentInsets.bottom
        )

        self.contentTopConstraint = contentTopConstraint
        self.contentLeadingConstraint = contentLeadingConstraint
        self.contentTrailingConstraint = contentTrailingConstraint
        self.contentBottomConstraint = contentBottomConstraint

        NSLayoutConstraint.activate([
            contentTopConstraint,
            contentLeadingConstraint,
            contentTrailingConstraint,
            contentBottomConstraint
        ])
    }

    /// Applies incoming or outgoing bubble colors, corner radius, and tail corner masking.
    package func configure(
        isOutgoing: Bool,
        roundsAllCorners: Bool = false,
        theme: ConsultantTheme = .defaultTheme
    ) {
        self.theme = theme
        backgroundColor = MessageBubbleStyle.bubbleColor(
            isOutgoing: isOutgoing,
            theme: theme
        )
        layer.cornerRadius = theme.roundedElements ? 12 : 4
        layer.maskedCorners = roundsAllCorners
            ? Self.allCorners
            : tailCorners(isOutgoing: isOutgoing)
    }

    /// Updates the content insets by changing the internal content constraints.
    package func setContentInsets(_ contentInsets: UIEdgeInsets) {
        self.contentInsets = contentInsets
        contentTopConstraint?.constant = contentInsets.top
        contentLeadingConstraint?.constant = contentInsets.left
        contentTrailingConstraint?.constant = -contentInsets.right
        contentBottomConstraint?.constant = -contentInsets.bottom
    }

    private func tailCorners(isOutgoing: Bool) -> CACornerMask {
        isOutgoing
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }
}

package extension MessageBubbleView {

    private static let allCorners: CACornerMask = [
        .layerMinXMinYCorner,
        .layerMaxXMinYCorner,
        .layerMinXMaxYCorner,
        .layerMaxXMaxYCorner
    ]
}
