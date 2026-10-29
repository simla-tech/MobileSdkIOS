import UIKit

/// Displays the chat composer with text input, attachment previews, and send controls.
package final class InputBar: UIView {

    private static let horizontalSpacing: CGFloat = 10
    private static let topSpacing: CGFloat = 8
    private static let bottomSpacing: CGFloat = 8
    private static let minTextViewHeight: CGFloat = 36
    private static let maxTextViewHeight: CGFloat = 180
    private static let buttonSize: CGFloat = 36
    private static let attachmentButtonSize: CGFloat = 28
    private static let attachmentButtonBottomSpacing: CGFloat = 12
    private static let sendButtonLeadingSpacing: CGFloat = 7
    private static let sendButtonTrailingSpacing: CGFloat = 12
    private static let roundedCornerRadius: CGFloat = 10
    private static let rectangularCornerRadius: CGFloat = 4
    private static let separatorHeight: CGFloat = 1
    private static let attachmentCellSize = CGSize(width: 86, height: 86)
    private static let attachmentsHeight: CGFloat = 102
    private static let attachmentItemSpacing: CGFloat = 8
    private static let attachmentSectionInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    private static let attachmentVisibilityAnimationDuration: TimeInterval = 0.2
    private static let sendButtonColorAnimationDuration: TimeInterval = 0.2

    private lazy var topSeparatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var attachmentsSeparatorView: UIView = {
        let view = UIView()
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var attachmentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(ConsultantImageResource.attachmentIcon.templateImage, for: .normal)
        button.addTarget(self, action: #selector(attachmentButtonTapped), for: .touchUpInside)
        button.accessibilityIdentifier = "attachmentMenuButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var textView: InputTextView = {
        let view = InputTextView()
        view.layer.borderWidth = 0.5
        view.font = MessageBubbleStyle.messageFont
        view.placeholder = ConsultantLocalization.messageInputPlaceholder.localized
        view.accessibilityIdentifier = "messageInputTextView"
        view.returnKeyType = .default
        view.delegate = self
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        view.textContainer.lineFragmentPadding = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .custom)
        button.adjustsImageWhenDisabled = false
        button.setImage(ConsultantImageResource.sendIcon.templateImage, for: .normal)
        button.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        button.accessibilityIdentifier = "sendMessageButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var attachmentsCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = Self.attachmentCellSize
        layout.sectionInset = Self.attachmentSectionInset
        layout.minimumLineSpacing = Self.attachmentItemSpacing
        layout.minimumInteritemSpacing = Self.attachmentItemSpacing

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alpha = 0
        collectionView.isHidden = true
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "inputAttachmentsCollectionView"
        collectionView.register(
            InputAttachmentCollectionViewCell.self,
            forCellWithReuseIdentifier: CellReuseIdentifier.inputAttachment.rawValue
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private var textViewHeightConstraint: NSLayoutConstraint?
    private var textViewTopConstraint: NSLayoutConstraint?
    private var attachmentsCollectionHeightConstraint: NSLayoutConstraint?
    private var inputAttachments: [InputAttachment] = []
    private var cachedIntrinsicContentSize = CGSize(width: UIView.noIntrinsicMetric, height: 0)
    private var canSendMessages = false
    private var lastMeasuredTextViewWidth: CGFloat = 0
    private var theme = ConsultantTheme.defaultTheme

    /// Called when the user taps send with valid text or sendable attachments.
    package var onSend: ((String) -> Void)?

    /// Called when the user taps the attachment button.
    package var onOpenAttachmentMenu: ((UIView) -> Void)?

    /// Called when the user removes an attachment from the input preview strip.
    package var onRemoveInputAttachment: ((UUID) -> Void)?

    /// Called when the user retries a failed attachment upload.
    package var onRetryInputAttachment: ((UUID) -> Void)?

    /// Called when text or attachments change the input bar intrinsic height.
    package var onIntrinsicContentSizeChange: (() -> Void)?

    /// Current text entered in the composer.
    package var messageText: String {
        textView.text ?? ""
    }

    private var canSendInputAttachments: Bool {
        inputAttachments.allSatisfy(\.canSend)
    }

    /// Current height requested by the input bar for its text and attachment content.
    package override var intrinsicContentSize: CGSize {
        cachedIntrinsicContentSize
    }

    /// Recalculates text height when layout gives the text view a new width.
    package override func layoutSubviews() {
        super.layoutSubviews()

        guard abs(textView.bounds.width - lastMeasuredTextViewWidth) > 0.5 else {
            return
        }

        updateTextViewHeight()
    }

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
        updateTextViewHeight()
        applyTheme()
        updateSendControls()
    }

    private func setupSubviews() {
        addSubview(topSeparatorView)
        addSubview(attachmentsCollectionView)
        addSubview(attachmentsSeparatorView)
        addSubview(attachmentButton)
        addSubview(textView)
        addSubview(sendButton)
    }

    private func setupConstraints() {
        let textViewHeightConstraint = textView.heightAnchor.constraint(
            equalToConstant: Self.minTextViewHeight
        )
        let textViewTopConstraint = textView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topSpacing)
        let attachmentsCollectionHeightConstraint = attachmentsCollectionView.heightAnchor.constraint(
            equalToConstant: 0
        )
        self.textViewHeightConstraint = textViewHeightConstraint
        self.textViewTopConstraint = textViewTopConstraint
        self.attachmentsCollectionHeightConstraint = attachmentsCollectionHeightConstraint

        NSLayoutConstraint.activate([
            topSeparatorView.topAnchor.constraint(equalTo: topAnchor),
            topSeparatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparatorView.heightAnchor.constraint(equalToConstant: Self.separatorHeight),

            attachmentsCollectionView.topAnchor.constraint(equalTo: topSeparatorView.bottomAnchor),
            attachmentsCollectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentsCollectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            attachmentsCollectionHeightConstraint,

            attachmentsSeparatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentsSeparatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            attachmentsSeparatorView.bottomAnchor.constraint(equalTo: attachmentsCollectionView.bottomAnchor),
            attachmentsSeparatorView.heightAnchor.constraint(equalToConstant: Self.separatorHeight),

            attachmentButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalSpacing),
            attachmentButton.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Self.attachmentButtonBottomSpacing
            ),
            attachmentButton.widthAnchor.constraint(equalToConstant: Self.attachmentButtonSize),
            attachmentButton.heightAnchor.constraint(equalToConstant: Self.attachmentButtonSize),

            textView.leadingAnchor.constraint(
                equalTo: attachmentButton.trailingAnchor,
                constant: Self.horizontalSpacing
            ),
            textViewTopConstraint,
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomSpacing),
            textViewHeightConstraint,

            sendButton.leadingAnchor.constraint(
                equalTo: textView.trailingAnchor,
                constant: Self.sendButtonLeadingSpacing
            ),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.sendButtonTrailingSpacing),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomSpacing),
            sendButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Self.buttonSize)
        ])
    }

    private func updateTextViewHeight() {
        lastMeasuredTextViewWidth = textView.bounds.width
        let fittingSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        let requiredHeight = textView.sizeThatFits(fittingSize).height.rounded(.up)
        let textViewHeight = min(
            Self.maxTextViewHeight,
            max(Self.minTextViewHeight, requiredHeight)
        )
        let shouldScrollText = requiredHeight > Self.maxTextViewHeight
        let attachmentsHeight = inputAttachments.isEmpty ? 0 : Self.attachmentsHeight
        let intrinsicHeight = Self.topSpacing + attachmentsHeight + textViewHeight + Self.bottomSpacing
        let oldIntrinsicContentSize = cachedIntrinsicContentSize

        textViewHeightConstraint?.constant = textViewHeight
        textView.isScrollEnabled = shouldScrollText
        cachedIntrinsicContentSize = CGSize(width: UIView.noIntrinsicMetric, height: intrinsicHeight)

        guard abs(oldIntrinsicContentSize.height - cachedIntrinsicContentSize.height) > 0.5 else {
            return
        }

        invalidateIntrinsicContentSize()
        onIntrinsicContentSizeChange?()
    }

    private func applyTheme() {
        backgroundColor = theme.bottomBarColor
        topSeparatorView.backgroundColor = theme.dividerColor
        attachmentsSeparatorView.backgroundColor = theme.dividerColor
        attachmentButton.tintColor = theme.areaIconColor
        textView.backgroundColor = theme.areaBackgroundColor
        textView.layer.cornerRadius = theme.roundedElements
            ? Self.roundedCornerRadius
            : Self.rectangularCornerRadius
        textView.layer.borderColor = theme.areaBorderColor.cgColor
        textView.textColor = theme.areaTextColor
        textView.placeholderColor = theme.placeholderTextColor
        sendButton.layer.cornerRadius = theme.roundedElements
            ? Self.roundedCornerRadius
            : Self.rectangularCornerRadius
    }

    private func updateSendControls() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSendableContent = !text.isEmpty || !inputAttachments.isEmpty
        let isSendButtonEnabled = canSendMessages && canSendInputAttachments && hasSendableContent

        textView.isEditable = canSendMessages
        textView.isSelectable = canSendMessages
        sendButton.isEnabled = isSendButtonEnabled
        sendButton.isUserInteractionEnabled = isSendButtonEnabled
        sendButton.tintColor = theme.mainIconColor

        let backgroundColor = isSendButtonEnabled
            ? theme.brandColor
            : UIColor(hex: 0x636F7F, alpha: 0.2)
        guard sendButton.backgroundColor != backgroundColor else {
            return
        }

        guard window != nil, !UIAccessibility.isReduceMotionEnabled else {
            sendButton.backgroundColor = backgroundColor
            return
        }

        UIView.animate(
            withDuration: Self.sendButtonColorAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.sendButton.backgroundColor = backgroundColor
        }
    }

    /// Enables or disables message composition controls.
    package func setCanSendMessages(_ canSend: Bool) {
        guard canSendMessages != canSend else {
            return
        }

        canSendMessages = canSend
        updateSendControls()
    }

    /// Clears the entered message text and refreshes composer layout.
    package func clearText() {
        textView.text = ""
        textViewDidChange(textView)
    }

    /// Replaces input attachment previews and updates composer height and send availability.
    package func setInputAttachments(_ attachments: [InputAttachment]) {
        guard inputAttachments != attachments else {
            return
        }

        let oldAttachmentCount = inputAttachments.count
        inputAttachments = attachments
        attachmentsCollectionView.reloadData()
        updateAttachmentsVisibility(animated: oldAttachmentCount != attachments.count)
        updateTextViewHeight()
        updateSendControls()

        guard attachments.count > oldAttachmentCount, !attachments.isEmpty else {
            return
        }

        let indexPath = IndexPath(item: attachments.count - 1, section: 0)
        attachmentsCollectionView.scrollToItem(at: indexPath, at: .right, animated: true)
    }

    /// Applies consultant colors and shape settings to input controls.
    package func setTheme(_ theme: ConsultantTheme) {
        self.theme = theme
        applyTheme()
        updateSendControls()
    }

    @objc private func sendButtonTapped() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendMessages, canSendInputAttachments, !text.isEmpty || !inputAttachments.isEmpty else {
            return
        }

        onSend?(text)
    }

    @objc private func attachmentButtonTapped() {
        onOpenAttachmentMenu?(attachmentButton)
    }

    private func updateAttachmentsVisibility(animated: Bool) {
        let isVisible = !inputAttachments.isEmpty
        let updates = {
            self.attachmentsCollectionView.alpha = isVisible ? 1 : 0
            self.attachmentsSeparatorView.alpha = isVisible ? 1 : 0
        }

        attachmentsCollectionView.isHidden = false
        attachmentsCollectionHeightConstraint?.constant = isVisible ? Self.attachmentsHeight : 0
        textViewTopConstraint?.constant = Self.topSpacing + (isVisible ? Self.attachmentsHeight : 0)

        if animated {
            UIView.animate(
                withDuration: Self.attachmentVisibilityAnimationDuration,
                animations: updates
            ) { [weak self] _ in
                self?.attachmentsCollectionView.isHidden = !isVisible
            }
        } else {
            updates()
            attachmentsCollectionView.isHidden = !isVisible
        }
    }
}

extension InputBar: UITextViewDelegate {

    /// Updates placeholder visibility, height, and send availability after text changes.
    package func textViewDidChange(_ textView: UITextView) {
        self.textView.updatePlaceholderVisibility()
        updateTextViewHeight()
        updateSendControls()
    }
}

extension InputBar: UICollectionViewDataSource, UICollectionViewDelegate {

    /// Returns the number of attachment previews currently shown above the text input.
    package func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        inputAttachments.count
    }

    /// Configures an attachment preview cell and forwards remove or retry actions.
    package func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            inputAttachments.indices.contains(indexPath.item),
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CellReuseIdentifier.inputAttachment.rawValue,
                for: indexPath
            ) as? InputAttachmentCollectionViewCell
        else {
            return UICollectionViewCell()
        }

        let attachment = inputAttachments[indexPath.item]
        cell.configure(attachment)
        cell.onRemove = { [weak self, attachmentID = attachment.id] in
            self?.onRemoveInputAttachment?(attachmentID)
        }
        cell.onRetry = { [weak self, attachmentID = attachment.id] in
            self?.onRetryInputAttachment?(attachmentID)
        }
        return cell
    }
}
