import UIKit

/// Renders the shared contact form content used by the full-screen form and chat message bubble.
///
/// The view builds visible text fields from `ConsultantContactForm.fields`, applies user prefill
/// values, handles personal-data and marketing consent toggles, validates required fields, and
/// emits `ContactFormSubmitData` when the visitor submits the form.
package final class ContactFormContentView: UIView {

    package static let fieldHeight: CGFloat = 44
    private static let buttonHeight: CGFloat = 48
    private static let disabledButtonColor = UIColor(red: 0.87, green: 0.89, blue: 0.90, alpha: 1.0)
    private static let disabledButtonTextColor = UIColor(red: 0.54, green: 0.59, blue: 0.65, alpha: 1.0)
    private static let avatarSize: CGFloat = 64
    private static let avatarBackgroundSize: CGFloat = 56
    private static let avatarBackgroundCornerRadius: CGFloat = 28
    private static let fullScreenContentSpacing: CGFloat = 32
    private static let messageContentSpacing: CGFloat = 12
    private static let fullScreenFormSpacing: CGFloat = 32
    private static let messageFormSpacing: CGFloat = 12
    private static let fieldsSpacing: CGFloat = 12
    private static let checkboxSize: CGFloat = 18
    private static let checkboxTextSpacing: CGFloat = 6
    private static let errorColor = UIColor(red: 1.0, green: 0.33, blue: 0.33, alpha: 1.0)
    private static let standardContactFieldKeys: [ContactFormFieldKey] = [.name, .phone, .email]

    private lazy var contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "contactFormAvatarContainerView"
        return view
    }()

    private lazy var avatarBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = Self.avatarBackgroundCornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarImageView: UIImageView = {
        let view = UIImageView()
        view.image = ConsultantImageResource.contactAvatar.image
            ?? ConsultantImageResource.person.image
        view.contentMode = .scaleAspectFit
        view.accessibilityIdentifier = "contactFormAvatarImageView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.messageFont
        label.textAlignment = .center
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "contactFormMessageLabel"
        return label
    }()

    private lazy var formStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        return view
    }()

    private lazy var fieldsStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .fill
        view.distribution = .fill
        view.spacing = Self.fieldsSpacing
        return view
    }()

    private lazy var personalDataConsentControl: UIControl = {
        let control = UIControl()
        control.isHidden = true
        control.addTarget(
            self,
            action: #selector(togglePersonalDataConsent),
            for: .touchUpInside
        )
        control.accessibilityIdentifier = "contactFormPersonalDataControl"
        return control
    }()

    private lazy var personalDataCheckboxButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(
            self,
            action: #selector(togglePersonalDataConsent),
            for: .touchUpInside
        )
        button.accessibilityIdentifier = "contactFormPersonalDataCheckbox"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var personalDataConsentTextView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.font = MessageBubbleStyle.regularSmallFont
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = makePersonalDataConsentText()
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue
        ]
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.accessibilityIdentifier = "contactFormPersonalDataLabel"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private lazy var marketingConsentControl: UIControl = {
        let control = UIControl()
        control.isHidden = true
        control.addTarget(
            self,
            action: #selector(toggleMarketingConsent),
            for: .touchUpInside
        )
        control.accessibilityIdentifier = "contactFormMarketingControl"
        return control
    }()

    private lazy var marketingConsentCheckboxButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(
            self,
            action: #selector(toggleMarketingConsent),
            for: .touchUpInside
        )
        button.accessibilityIdentifier = "contactFormMarketingCheckbox"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var marketingConsentLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = MessageBubbleStyle.regularSmallFont
        label.text = ConsultantLocalization.contactFormMarketingConsent.localized
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.accessibilityIdentifier = "contactFormMarketingLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularSmallFont
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "contactFormErrorLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var resultLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.messageFont
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "contactFormResultLabel"
        return label
    }()

    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = MessageBubbleStyle.semiboldLargeFont
        button.setTitle(ConsultantLocalization.contactFormSubmit.localized, for: .normal)
        button.setTitleColor(Self.disabledButtonTextColor, for: .disabled)
        button.isEnabled = false
        button.addTarget(
            self,
            action: #selector(submitContactForm),
            for: .touchUpInside
        )
        button.accessibilityIdentifier = "contactFormSubmitButton"
        return button
    }()

    private lazy var submitActivityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.hidesWhenStopped = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    package var onSubmit: ((ContactFormSubmitData) -> Void)?
    package var onPersonalDataLinkTap: ((URL) -> Void)?

    private var fieldTextFields: [ContactFormFieldKey: UITextField] = [:]
    private var requiredFieldKeys: Set<ContactFormFieldKey> = []
    private var requiresPersonalDataConsent = false
    private var isPersonalDataConsentAccepted = false
    private var hasMarketingConsent = false
    private var isMarketingConsentRequired = false
    private var isMarketingConsentAccepted = false
    private var isSubmitting = false
    private var isSubmitted = false
    private var currentSubmitErrorMessage: String?
    private var currentForm: ContactForm?
    private var personalDataLink: URL?
    private var theme = ConsultantTheme.defaultTheme

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    package func prepareForReuse() {
        fieldTextFields.values.forEach { $0.text = nil }
        isSubmitted = false
        currentSubmitErrorMessage = nil
        updateErrorView()
        setSubmitting(false)
        onSubmit = nil
        onPersonalDataLinkTap = nil
        personalDataLink = nil
    }

    private func setup() {
        backgroundColor = .clear
        setupSubviews()
        setupConstraints()
        applyTheme()
    }

    private func setupSubviews() {
        addSubview(contentStackView)
        avatarContainerView.addSubview(avatarBackgroundView)
        avatarContainerView.addSubview(avatarImageView)
        personalDataConsentControl.addSubview(personalDataCheckboxButton)
        personalDataConsentControl.addSubview(personalDataConsentTextView)
        marketingConsentControl.addSubview(marketingConsentCheckboxButton)
        marketingConsentControl.addSubview(marketingConsentLabel)
        submitButton.addSubview(submitActivityIndicator)

        contentStackView.addArrangedSubview(avatarContainerView)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(formStackView)
        formStackView.addArrangedSubview(fieldsStackView)
        formStackView.addArrangedSubview(errorLabel)
        formStackView.addArrangedSubview(resultLabel)
        formStackView.addArrangedSubview(submitButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarContainerView.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarBackgroundView.centerXAnchor.constraint(equalTo: avatarContainerView.centerXAnchor),
            avatarBackgroundView.centerYAnchor.constraint(equalTo: avatarContainerView.centerYAnchor),
            avatarBackgroundView.widthAnchor.constraint(equalToConstant: Self.avatarBackgroundSize),
            avatarBackgroundView.heightAnchor.constraint(equalToConstant: Self.avatarBackgroundSize),
            avatarImageView.centerXAnchor.constraint(equalTo: avatarContainerView.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarContainerView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Self.avatarSize),

            personalDataCheckboxButton.leadingAnchor.constraint(equalTo: personalDataConsentControl.leadingAnchor),
            personalDataCheckboxButton.topAnchor.constraint(equalTo: personalDataConsentControl.topAnchor),
            personalDataCheckboxButton.widthAnchor.constraint(equalToConstant: Self.checkboxSize),
            personalDataCheckboxButton.heightAnchor.constraint(equalToConstant: Self.checkboxSize),
            personalDataConsentTextView.leadingAnchor.constraint(
                equalTo: personalDataCheckboxButton.trailingAnchor,
                constant: Self.checkboxTextSpacing
            ),
            personalDataConsentTextView.topAnchor.constraint(equalTo: personalDataConsentControl.topAnchor),
            personalDataConsentTextView.trailingAnchor.constraint(equalTo: personalDataConsentControl.trailingAnchor),
            personalDataConsentTextView.bottomAnchor.constraint(equalTo: personalDataConsentControl.bottomAnchor),

            marketingConsentCheckboxButton.leadingAnchor.constraint(equalTo: marketingConsentControl.leadingAnchor),
            marketingConsentCheckboxButton.topAnchor.constraint(equalTo: marketingConsentControl.topAnchor),
            marketingConsentCheckboxButton.widthAnchor.constraint(equalToConstant: Self.checkboxSize),
            marketingConsentCheckboxButton.heightAnchor.constraint(equalToConstant: Self.checkboxSize),
            marketingConsentLabel.leadingAnchor.constraint(
                equalTo: marketingConsentCheckboxButton.trailingAnchor,
                constant: Self.checkboxTextSpacing
            ),
            marketingConsentLabel.topAnchor.constraint(equalTo: marketingConsentControl.topAnchor),
            marketingConsentLabel.trailingAnchor.constraint(equalTo: marketingConsentControl.trailingAnchor),
            marketingConsentLabel.bottomAnchor.constraint(equalTo: marketingConsentControl.bottomAnchor),

            submitButton.heightAnchor.constraint(equalToConstant: Self.buttonHeight),
            submitActivityIndicator.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            submitActivityIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor)
        ])
    }

    private func applyTheme() {
        avatarImageView.tintColor = theme.brandColor
        messageLabel.textColor = theme.primaryTextColor
        resultLabel.textColor = theme.primaryTextColor
        personalDataCheckboxButton.tintColor = theme.brandColor
        personalDataConsentTextView.attributedText = makePersonalDataConsentText()
        marketingConsentCheckboxButton.tintColor = theme.brandColor
        marketingConsentLabel.textColor = theme.primaryTextColor
        errorLabel.textColor = Self.errorColor
        submitButton.tintColor = theme.mainIconColor
        submitButton.layer.cornerRadius = theme.roundedElements
            ? MessageLayout.contentCornerRadius
            : MessageLayout.compactCornerRadius
        submitButton.setTitleColor(theme.mainTextColor, for: .normal)
        submitActivityIndicator.color = theme.mainIconColor

        fieldTextFields.values.forEach { textField in
            textField.backgroundColor = theme.areaBackgroundColor
            textField.layer.cornerRadius = theme.roundedElements
                ? MessageLayout.contentCornerRadius
                : MessageLayout.compactCornerRadius
            textField.layer.borderColor = theme.areaBorderColor.cgColor
            textField.textColor = theme.areaTextColor
            if let placeholder = textField.placeholder {
                textField.attributedPlaceholder = NSAttributedString(
                    string: placeholder,
                    attributes: [.foregroundColor: theme.placeholderTextColor]
                )
            }
        }
    }

    package func configure(
        form: ContactForm,
        layoutMode: LayoutMode
    ) {
        currentForm = form
        isSubmitted = form.isSubmitted
        currentSubmitErrorMessage = form.submitErrorMessage?.nilIfEmpty
        setSubmitting(false)

        let fields = makeContactFieldDescriptors(form: form)
        let needsPersonalDataConsent = form.fields[.personalData] != nil
        let marketingConsentField = form.fields[.marketingConsent]
        let needsMarketingConsent = marketingConsentField != nil
        guard !fields.isEmpty || needsPersonalDataConsent || needsMarketingConsent else {
            isHidden = true
            return
        }

        isHidden = false
        fieldTextFields = [:]
        requiredFieldKeys = Set(fields.filter(\.isRequired).map(\.key))
        requiresPersonalDataConsent = needsPersonalDataConsent
        isPersonalDataConsentAccepted = false
        hasMarketingConsent = needsMarketingConsent
        isMarketingConsentRequired = marketingConsentField?.required == true
        isMarketingConsentAccepted = false

        configureLayoutMode(layoutMode)

        messageLabel.text = Self.messageText(for: form)
        messageLabel.isHidden = messageLabel.text?.isEmpty != false
        formStackView.isHidden = false
        fieldsStackView.isHidden = form.isSubmitted
        errorLabel.isHidden = true
        resultLabel.text = Self.resultText(for: form)
        resultLabel.isHidden = !form.isSubmitted || resultLabel.text?.isEmpty != false
        submitButton.isHidden = form.isSubmitted

        fieldsStackView.arrangedSubviews.forEach { view in
            fieldsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if form.isSubmitted {
            fieldTextFields = [:]
            requiredFieldKeys = []
            requiresPersonalDataConsent = false
            isPersonalDataConsentAccepted = false
            hasMarketingConsent = false
            isMarketingConsentRequired = false
            isMarketingConsentAccepted = false
            currentSubmitErrorMessage = nil
            updateErrorView()
            updateSubmitLoadingState()
            updateSubmitButtonState()
            return
        }

        fields.forEach { descriptor in
            fieldsStackView.addArrangedSubview(makeContactTextField(descriptor: descriptor))
        }

        if requiresPersonalDataConsent {
            fieldsStackView.addArrangedSubview(personalDataConsentControl)
        }

        if hasMarketingConsent {
            fieldsStackView.addArrangedSubview(marketingConsentControl)
        }

        updatePersonalDataConsentView()
        updateMarketingConsentView()
        updateErrorView()
        updateSubmitLoadingState()
        updateSubmitButtonState()
    }

    package func setPersonalDataLink(_ link: URL?) {
        personalDataLink = link
        personalDataConsentTextView.attributedText = makePersonalDataConsentText()
    }

    package func setTheme(_ theme: ConsultantTheme) {
        self.theme = theme
        applyTheme()
        updateSubmitButtonState()
    }

    package func setSubmitting(_ isSubmitting: Bool) {
        self.isSubmitting = isSubmitting
        updateSubmitLoadingState()
        updateSubmitButtonState()
    }

    package func setSubmitError(_ message: String?) {
        currentSubmitErrorMessage = message?.nilIfEmpty
        updateErrorView()
    }

    package func submitButtonFrame(in view: UIView) -> CGRect {
        submitButton.convert(submitButton.bounds, to: view)
    }

    private func configureLayoutMode(_ layoutMode: LayoutMode) {
        avatarContainerView.isHidden = layoutMode == .messageBubble
        messageLabel.textAlignment = layoutMode == .fullScreen ? .center : .left
        contentStackView.spacing = layoutMode == .fullScreen
            ? Self.fullScreenContentSpacing
            : Self.messageContentSpacing
        formStackView.spacing = layoutMode == .fullScreen
            ? Self.fullScreenFormSpacing
            : Self.messageFormSpacing
    }

    private func makeContactFieldDescriptors(form: ContactForm) -> [ContactFieldDescriptor] {
        Self.visibleContactFieldKeys(form: form).compactMap { key in
            guard let field = form.fields[key] else { return nil }
            return makeContactFieldDescriptor(
                key: key,
                field: field,
                prefill: Self.standardContactFieldKeys.contains(key)
                    ? makePrefillValue(key: key, form: form)
                    : nil
            )
        }
    }

    private func makeContactFieldDescriptor(
        key: ContactFormFieldKey,
        field: ContactFormField,
        prefill: String?
    ) -> ContactFieldDescriptor {
        switch key {
        case .name:
            return ContactFieldDescriptor(
                key: key,
                title: ConsultantLocalization.contactFormFieldName.localized,
                prefill: prefill,
                keyboardType: .default,
                textContentType: .name,
                autocapitalizationType: .words,
                isRequired: field.required
            )
        case .phone:
            return ContactFieldDescriptor(
                key: key,
                title: ConsultantLocalization.contactFormFieldPhone.localized,
                prefill: prefill,
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                autocapitalizationType: .none,
                isRequired: field.required
            )
        case .email:
            return ContactFieldDescriptor(
                key: key,
                title: ConsultantLocalization.contactFormFieldEmail.localized,
                prefill: prefill,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalizationType: .none,
                isRequired: field.required
            )
        case .custom("comment"):
            return ContactFieldDescriptor(
                key: key,
                title: ConsultantLocalization.contactFormFieldComment.localized,
                prefill: prefill,
                keyboardType: .default,
                textContentType: nil,
                autocapitalizationType: .sentences,
                isRequired: field.required
            )
        default:
            return ContactFieldDescriptor(
                key: key,
                title: key.rawValue,
                prefill: prefill,
                keyboardType: .default,
                textContentType: nil,
                autocapitalizationType: .sentences,
                isRequired: field.required
            )
        }
    }

    private func makePrefillValue(
        key: ContactFormFieldKey,
        form: ContactForm
    ) -> String? {
        if let fieldValue = form.fieldValues[key.rawValue] {
            return fieldValue
        }

        switch key {
        case .name:
            return form.prefill.name
        case .phone:
            return form.prefill.phone
        case .email:
            return form.prefill.email
        default:
            return form.fieldValues[key.rawValue]
        }
    }

    private func makeContactTextField(descriptor: ContactFieldDescriptor) -> UITextField {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.layer.borderWidth = 0.5
        textField.font = MessageBubbleStyle.semiboldLargeFont
        textField.keyboardType = descriptor.keyboardType
        textField.textContentType = descriptor.textContentType
        textField.autocapitalizationType = descriptor.autocapitalizationType
        textField.autocorrectionType = .no
        textField.text = descriptor.prefill
        textField.addTarget(
            self,
            action: #selector(contactTextFieldDidChange),
            for: .editingChanged
        )
        textField.attributedPlaceholder = NSAttributedString(
            string: descriptor.title + (descriptor.isRequired ? " *" : ""),
            attributes: [
                .foregroundColor: theme.placeholderTextColor
            ]
        )
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        textField.rightViewMode = .always
        textField.accessibilityIdentifier =
            "contactForm\(descriptor.key.rawValue.capitalized)TextField"

        NSLayoutConstraint.activate([
            textField.heightAnchor.constraint(equalToConstant: Self.fieldHeight)
        ])

        fieldTextFields[descriptor.key] = textField
        applyTheme()
        return textField
    }

    @objc private func contactTextFieldDidChange() {
        clearDisplayedSubmitError()
        updateSubmitButtonState()
    }

    @objc private func togglePersonalDataConsent() {
        guard requiresPersonalDataConsent, !isSubmitting, !isSubmitted else { return }
        isPersonalDataConsentAccepted.toggle()
        clearDisplayedSubmitError()
        updatePersonalDataConsentView()
        updateSubmitButtonState()
    }

    @objc private func toggleMarketingConsent() {
        guard hasMarketingConsent, !isSubmitting, !isSubmitted else { return }
        isMarketingConsentAccepted.toggle()
        clearDisplayedSubmitError()
        updateMarketingConsentView()
        updateSubmitButtonState()
    }

    @objc private func submitContactForm() {
        guard submitButton.isEnabled, !isSubmitting, !isSubmitted else { return }

        endEditing(true)
        onSubmit?(
            ContactFormSubmitData(
                name: contactFieldValue(for: .name),
                email: contactFieldValue(for: .email),
                phone: contactFieldValue(for: .phone),
                comment: contactFieldValue(for: .custom("comment")),
                marketingConsent: hasMarketingConsent ? isMarketingConsentAccepted : nil,
                actionID: currentForm?.actionID,
                kind: currentForm?.kind ?? .contact
            )
        )
    }

    private func contactFieldValue(for key: ContactFormFieldKey) -> String? {
        fieldTextFields[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func updatePersonalDataConsentView() {
        personalDataConsentControl.isHidden = !requiresPersonalDataConsent

        let image = isPersonalDataConsentAccepted
            ? ConsultantImageResource.checkboxOn.image
            : ConsultantImageResource.checkboxOff.image
        personalDataCheckboxButton.setImage(image, for: .normal)
        personalDataCheckboxButton.accessibilityValue = isPersonalDataConsentAccepted
            ? ConsultantLocalization.commonOn.localized
            : ConsultantLocalization.commonOff.localized
    }

    private func updateMarketingConsentView() {
        marketingConsentControl.isHidden = !hasMarketingConsent

        let image = isMarketingConsentAccepted
            ? ConsultantImageResource.checkboxOn.image
            : ConsultantImageResource.checkboxOff.image
        marketingConsentCheckboxButton.setImage(image, for: .normal)
        marketingConsentCheckboxButton.accessibilityValue = isMarketingConsentAccepted
            ? ConsultantLocalization.commonOn.localized
            : ConsultantLocalization.commonOff.localized
    }

    private func updateErrorView() {
        errorLabel.text = currentSubmitErrorMessage
        errorLabel.isHidden = currentSubmitErrorMessage == nil
    }

    private func clearDisplayedSubmitError() {
        guard currentSubmitErrorMessage != nil else {
            return
        }

        currentSubmitErrorMessage = nil
        updateErrorView()
    }

    private func updateSubmitButtonState() {
        let requiredFieldsAreFilled = requiredFieldKeys.allSatisfy { key in
            fieldTextFields[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let personalDataIsAccepted = !requiresPersonalDataConsent || isPersonalDataConsentAccepted
        let marketingConsentIsAccepted = !isMarketingConsentRequired || isMarketingConsentAccepted
        let isEnabled = requiredFieldsAreFilled &&
            personalDataIsAccepted &&
            marketingConsentIsAccepted &&
            !isSubmitting &&
            !isSubmitted

        submitButton.isEnabled = isEnabled
        submitButton.backgroundColor = isEnabled || isSubmitting
            ? theme.brandColor
            : Self.disabledButtonColor
    }

    private func updateSubmitLoadingState() {
        let isInputEnabled = !isSubmitting && !isSubmitted
        fieldTextFields.values.forEach { $0.isEnabled = isInputEnabled }
        personalDataConsentControl.isEnabled = isInputEnabled
        personalDataCheckboxButton.isEnabled = isInputEnabled
        marketingConsentControl.isEnabled = isInputEnabled
        marketingConsentCheckboxButton.isEnabled = isInputEnabled

        if isSubmitting {
            submitButton.setTitle(nil, for: .normal)
            submitActivityIndicator.startAnimating()
        } else if isSubmitted {
            submitActivityIndicator.stopAnimating()
            submitButton.setTitle(ConsultantLocalization.contactFormSubmitted.localized, for: .normal)
        } else {
            submitActivityIndicator.stopAnimating()
            submitButton.setTitle(ConsultantLocalization.contactFormSubmit.localized, for: .normal)
        }
    }

    private func makePersonalDataConsentText() -> NSAttributedString {
        let text = ConsultantLocalization.contactFormPersonalDataConsent.localized
        let linkText = ConsultantLocalization.contactFormPersonalDataLinkText.localized
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: theme.primaryTextColor,
                .font: MessageBubbleStyle.regularSmallFont
            ]
        )
        let linkRange = (text as NSString).range(of: linkText)
        if linkRange.location != NSNotFound {
            var linkAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.systemBlue
            ]
            if let personalDataLink {
                linkAttributes[.link] = personalDataLink
            }
            attributedText.addAttributes(linkAttributes, range: linkRange)
        }
        return attributedText
    }

}

extension ContactFormContentView: UITextViewDelegate {

    package func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onPersonalDataLinkTap?(URL)
        return false
    }
}

package extension ContactFormContentView {

    enum LayoutMode {
        case fullScreen
        case messageBubble
    }

    private struct ContactFieldDescriptor {
        let key: ContactFormFieldKey
        let title: String
        let prefill: String?
        let keyboardType: UIKeyboardType
        let textContentType: UITextContentType?
        let autocapitalizationType: UITextAutocapitalizationType
        let isRequired: Bool
    }
}

package extension ContactFormContentView {

    static let formWidth: CGFloat = 326

    static func preferredHeight(
        for form: ContactForm,
        width: CGFloat,
        layoutMode: LayoutMode
    ) -> CGFloat {
        if form.isSubmitted {
            let messageHeight = textHeight(
                messageText(for: form),
                width: width,
                font: MessageBubbleStyle.messageFont
            )
            let resultHeight = textHeight(
                resultText(for: form),
                width: width,
                font: MessageBubbleStyle.messageFont
            )
            let showsAvatar = layoutMode == .fullScreen
            let contentSpacing = layoutMode == .fullScreen
                ? Self.fullScreenContentSpacing
                : Self.messageContentSpacing
            let visibleBlocks = (showsAvatar ? 1 : 0)
                + (messageHeight > 0 ? 1 : 0)
                + (resultHeight > 0 ? 1 : 0)
            let contentGapHeight = CGFloat(max(0, visibleBlocks - 1)) * contentSpacing

            return ceil(
                (showsAvatar ? Self.avatarSize : 0)
                    + messageHeight
                    + resultHeight
                    + contentGapHeight
            )
        }

        let fields = visibleContactFieldKeys(form: form).count
        let hasPersonalDataConsent = form.fields[.personalData] != nil
        let hasMarketingConsent = form.fields[.marketingConsent] != nil
        let fieldBlocks = fields
            + (hasPersonalDataConsent ? 1 : 0)
            + (hasMarketingConsent ? 1 : 0)
        let fieldsHeight = CGFloat(fields) * Self.fieldHeight
            + checkboxHeight(
                text: ConsultantLocalization.contactFormPersonalDataConsent.localized,
                width: width
            ) * CGFloat(hasPersonalDataConsent ? 1 : 0)
            + checkboxHeight(
                text: ConsultantLocalization.contactFormMarketingConsent.localized,
                width: width
            ) * CGFloat(hasMarketingConsent ? 1 : 0)
            + CGFloat(max(0, fieldBlocks - 1)) * Self.fieldsSpacing
        let formSpacing = layoutMode == .fullScreen
            ? Self.fullScreenFormSpacing
            : Self.messageFormSpacing
        let errorHeight = textHeight(
            form.submitErrorMessage?.nilIfEmpty,
            width: width,
            font: MessageBubbleStyle.regularSmallFont
        )
        let formHeight = fieldsHeight
            + formSpacing
            + (errorHeight > 0 ? errorHeight + formSpacing : 0)
            + Self.buttonHeight
        let messageHeight = textHeight(
            messageText(for: form),
            width: width,
            font: MessageBubbleStyle.messageFont
        )
        let showsAvatar = layoutMode == .fullScreen
        let contentSpacing = layoutMode == .fullScreen
            ? Self.fullScreenContentSpacing
            : Self.messageContentSpacing
        let visibleBlocks = (showsAvatar ? 1 : 0) + (messageHeight > 0 ? 1 : 0) + 1
        let contentGapHeight = CGFloat(max(0, visibleBlocks - 1)) * contentSpacing

        return ceil(
            (showsAvatar ? Self.avatarSize : 0)
                + messageHeight
                + formHeight
                + contentGapHeight
        )
    }
}

private extension ContactFormContentView {

    static func messageText(for form: ContactForm) -> String {
        return form.text?.nilIfEmpty
            ?? (form.kind == .offline
                ? ConsultantLocalization.offlineDefaultText.localized
                : ConsultantLocalization.contactFormDefaultText.localized)
    }

    static func resultText(for form: ContactForm) -> String {
        form.resultText?.nilIfEmpty
            ?? (form.kind == .offline
                ? ConsultantLocalization.offlineFormDefaultResultText.localized
                : ConsultantLocalization.contactFormDefaultText.localized)
    }

    static func visibleContactFieldKeys(form: ContactForm) -> [ContactFormFieldKey] {
        let customFields = form.fields.keys.filter {
            !standardContactFieldKeys.contains($0)
                && $0 != .personalData
                && $0 != .marketingConsent
        }

        return standardContactFieldKeys.filter { form.fields[$0] != nil } + customFields.sorted()
    }

    static func checkboxHeight(text: String, width: CGFloat) -> CGFloat {
        let labelWidth = max(1, width - Self.checkboxSize - Self.checkboxTextSpacing)
        let labelHeight = textHeight(
            text,
            width: labelWidth,
            font: MessageBubbleStyle.regularSmallFont
        )

        return max(Self.checkboxSize, labelHeight)
    }

    static func textHeight(
        _ text: String?,
        width: CGFloat,
        font: UIFont
    ) -> CGFloat {
        guard let text, !text.isEmpty else {
            return 0
        }

        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
        )
    }
}
