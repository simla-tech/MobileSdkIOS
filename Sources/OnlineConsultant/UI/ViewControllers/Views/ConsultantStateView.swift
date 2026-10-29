import UIKit

package final class ConsultantStateView: UIView {

    package enum Mode: Equatable {
        case hidden
        case loading
        case error
    }

    private lazy var activityIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.hidesWhenStopped = true
        view.accessibilityIdentifier = "consultantStateActivityIndicator"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "consultantStateTitleLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.background.cornerRadius = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        configuration.title = ConsultantLocalization.commonRetry.localized
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)
        button.accessibilityIdentifier = "consultantStateRetryButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var stackView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [
            activityIndicatorView,
            titleLabel,
            retryButton
        ])
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var mode: Mode = .hidden
    private var theme = ConsultantTheme.defaultTheme

    package var onRetry: (() -> Void)?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    package func setMode(_ mode: Mode) {
        guard self.mode != mode else {
            return
        }

        self.mode = mode
        applyMode()
    }

    package func setTheme(_ theme: ConsultantTheme) {
        self.theme = theme
        applyTheme()
    }

    private func setup() {
        accessibilityIdentifier = "consultantStateView"
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        applyTheme()
        applyMode()
    }

    private func applyTheme() {
        backgroundColor = theme.screenBackgroundColor
        activityIndicatorView.color = theme.brandColor
        titleLabel.textColor = theme.primaryTextColor
        var configuration = retryButton.configuration
        configuration?.baseBackgroundColor = theme.brandColor
        configuration?.baseForegroundColor = theme.mainTextColor
        retryButton.configuration = configuration
    }

    private func applyMode() {
        switch mode {
        case .hidden:
            isHidden = true
            activityIndicatorView.stopAnimating()
            titleLabel.isHidden = true
            retryButton.isHidden = true
        case .loading:
            isHidden = false
            titleLabel.isHidden = true
            retryButton.isHidden = true
            activityIndicatorView.startAnimating()
        case .error:
            isHidden = false
            activityIndicatorView.stopAnimating()
            titleLabel.text = ConsultantLocalization.commonError.localized
            titleLabel.isHidden = false
            retryButton.isHidden = false
        }
    }

    @objc private func retryButtonTapped() {
        onRetry?()
    }
}
