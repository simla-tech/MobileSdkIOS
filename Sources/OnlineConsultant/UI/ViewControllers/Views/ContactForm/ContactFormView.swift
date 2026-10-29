import UIKit

/// Displays a fullscreen contact form and keeps its submit button visible above the keyboard.
 package final class ContactFormView: UIView {

    private static let centerYOffset: CGFloat = 32
    package static let horizontalInset: CGFloat = 24
    package static let topInset: CGFloat = 32
    private static let defaultBottomSpacing: CGFloat = 24
    private static let keyboardButtonSpacing: CGFloat = 20

    private lazy var contentView: ContactFormContentView = {
        let view = ContactFormContentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var isObservingKeyboard = false
    private var theme = ConsultantTheme.defaultTheme

    /// Called when the user submits valid contact data.
     package var onSubmit: ((ContactFormSubmitData) -> Void)? {
        didSet {
            contentView.onSubmit = onSubmit
        }
    }

    package var onPersonalDataLinkTap: ((URL) -> Void)? {
        didSet {
            contentView.onPersonalDataLinkTap = onPersonalDataLinkTap
        }
    }

    private lazy var dismissKeyboardTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

     package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

     package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        unregisterForKeyboardNotifications()
    }

     package override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            unregisterForKeyboardNotifications()
        } else {
            registerForKeyboardNotifications()
        }
    }

    private func setup() {
        backgroundColor = theme.screenBackgroundColor
        setupGesture()
        setupSubviews()
        setupConstraints()
    }

    private func setupGesture() {
        addGestureRecognizer(dismissKeyboardTapGesture)
    }

    private func setupSubviews() {
        addSubview(contentView)
    }

    private func setupConstraints() {
        let formWidthConstraint = contentView.widthAnchor.constraint(
            equalToConstant: ContactFormContentView.formWidth
        )
        formWidthConstraint.priority = .defaultHigh

        let centerYConstraint = contentView.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: -Self.centerYOffset
        )
        centerYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerYConstraint,
            contentView.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: Self.horizontalInset
            ),
            contentView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Self.horizontalInset
            ),
            contentView.topAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
                constant: Self.topInset
            ),
            contentView.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor,
                constant: -Self.defaultBottomSpacing
            ),
            formWidthConstraint
        ])
    }

    /// Configures the fullscreen contact form content.
     package func configure(form: ContactForm) {
        contentView.configure(
            form: form,
            layoutMode: .fullScreen
        )
    }

    package func setPersonalDataLink(_ link: URL?) {
        contentView.setPersonalDataLink(link)
    }

    /// Updates the form submitting state and disables duplicate submissions while active.
     package func setSubmitting(_ isSubmitting: Bool) {
        contentView.setSubmitting(isSubmitting)
    }

    /// Displays or clears submit error text inside the form.
     package func setSubmitError(_ message: String?) {
        contentView.setSubmitError(message)
    }

    /// Applies consultant theme colors to the fullscreen form.
    package func setTheme(_ theme: ConsultantTheme) {
        self.theme = theme
        backgroundColor = theme.screenBackgroundColor
        contentView.setTheme(theme)
    }

    private func registerForKeyboardNotifications() {
        guard !isObservingKeyboard else { return }
        isObservingKeyboard = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func unregisterForKeyboardNotifications() {
        guard isObservingKeyboard else { return }
        isObservingKeyboard = false

        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let keyboardFrame = convert(endFrame, from: nil)
        let keyboardOverlap = max(0, bounds.maxY - keyboardFrame.minY)
        let verticalOffset = keyboardOverlap > 0
            ? makeKeyboardVerticalOffset(keyboardFrame: keyboardFrame)
            : 0

        updateContentVerticalOffset(verticalOffset, notification: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        updateContentVerticalOffset(0, notification: notification)
    }

    private func makeKeyboardVerticalOffset(keyboardFrame: CGRect) -> CGFloat {
        layoutIfNeeded()

        let currentOffset = max(0, -contentView.transform.ty)
        let submitButtonFrame = contentView.submitButtonFrame(in: self)
        let submitButtonMaxYWithoutTransform = submitButtonFrame.maxY + currentOffset

        return max(0, submitButtonMaxYWithoutTransform + Self.keyboardButtonSpacing - keyboardFrame.minY)
    }

    private func updateContentVerticalOffset(_ offset: CGFloat, notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 0
        let options = UIView.AnimationOptions(rawValue: UInt(curve << 16))

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: {
                self.contentView.transform = CGAffineTransform(translationX: 0, y: -offset)
            }
        )
    }
}

extension ContactFormView: UIGestureRecognizerDelegate {

     package func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var view = touch.view
        while let currentView = view {
            if currentView is UIControl || currentView is UITextField {
                return false
            }
            view = currentView.superview
        }

        return true
    }
}
