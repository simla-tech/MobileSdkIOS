import Core
import UIKit

/// Branding footer shown when backend `domain_config.footer` enables it.
package final class FooterBrandingView: UIView {

    /// Called when the visitor taps the branding footer.
    package var onTap: ((URL) -> Void)?

    private lazy var contentStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .horizontal
        view.alignment = .center
        view.distribution = .fill
        view.spacing = 4
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "consultantFooterBrandingContentStackView"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var madeInLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.regularCompactFont
        label.text = ConsultantLocalization.footerMadeIn.localized
        label.textColor = ConsultantTheme.defaultTheme.messageDateColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var brandLabel: UILabel = {
        let label = UILabel()
        label.font = MessageBubbleStyle.semiboldCompactFont
        label.textColor = ConsultantTheme.defaultTheme.messageDateColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var logoImageView: UIImageView = {
        let view = UIImageView()
        view.accessibilityIdentifier = "consultantFooterBrandingLogoImageView"
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(handleTap))
    }()

    private var logoLoadTask: ImageLoadTask?
    private var currentURL: URL?
    private var currentLogoURL: URL?

    package override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        logoLoadTask?.cancel()
    }

    /// Applies backend domain branding config and current consultant theme.
    package func configure(
        domainConfig: DomainConfig?,
        theme: ConsultantTheme
    ) {
        guard domainConfig?.footer == true else {
            resetLogoLoading()
            isHidden = true
            currentURL = nil
            currentLogoURL = nil
            return
        }

        isHidden = false
        backgroundColor = theme.bottomBarColor
        madeInLabel.textColor = theme.messageDateColor
        brandLabel.textColor = theme.messageDateColor
        currentURL = domainConfig?.url
        brandLabel.text = Self.brandName(from: domainConfig?.url)

        guard let logoURL = FooterBrandingLogoLoader.logoURL(
            domainConfig: domainConfig,
            theme: theme
        ) else {
            resetLogoLoading()
            currentLogoURL = nil
            return
        }

        guard currentLogoURL != logoURL else {
            return
        }

        resetLogoLoading()
        currentLogoURL = logoURL
        logoLoadTask = ImageLoader.shared.loadImage(from: logoURL) { [weak self] image in
            guard self?.currentLogoURL == logoURL else {
                return
            }

            self?.logoImageView.image = image
            self?.logoImageView.isHidden = image == nil
            self?.brandLabel.isHidden = image != nil
        }
    }

    private func setup() {
        setupSubviews()
        setupConstraints()
    }

    private func setupSubviews() {
        accessibilityIdentifier = "consultantFooterBrandingView"
        clipsToBounds = true
        addGestureRecognizer(tapGestureRecognizer)
        addSubview(contentStackView)
        contentStackView.addArrangedSubview(madeInLabel)
        contentStackView.addArrangedSubview(brandLabel)
        contentStackView.addArrangedSubview(logoImageView)
    }

    private func setupConstraints() {
        let contentTopConstraint = contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        let contentBottomConstraint = contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        contentTopConstraint.priority = .defaultHigh
        contentBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentTopConstraint,
            contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentBottomConstraint,
            contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            logoImageView.heightAnchor.constraint(equalToConstant: 17),
            logoImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 96)
        ])
    }

    private func resetLogoLoading() {
        logoLoadTask?.cancel()
        logoLoadTask = nil
        logoImageView.image = nil
        logoImageView.isHidden = true
        brandLabel.isHidden = false
    }

    @objc private func handleTap() {
        guard let currentURL else {
            return
        }

        onTap?(currentURL)
    }
}

private extension FooterBrandingView {

    static func brandName(from url: URL?) -> String {
        guard let host = url?.host?.lowercased() else {
            return "retailCRM"
        }

        return host.contains("simla") ? "Simla" : "retailCRM"
    }
}

/// Resolves and warms the same logo cache that the footer reads when it appears.
package enum FooterBrandingLogoLoader {

    package static func logoURL(
        domainConfig: DomainConfig?,
        theme: ConsultantTheme
    ) -> URL? {
        guard domainConfig?.footer == true, let url = domainConfig?.logo else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // These published branding assets have PNG equivalents in both themes.
        let knownPaths = ["retailcrm", "simla"].map {
            "/eu-central-1/retailcrm-static/branding/\($0)/logo/"
        }
        let directory = url.deletingLastPathComponent().path + "/"
        let name = url.deletingPathExtension().lastPathComponent
        let isStandardLogo = components.host?.lowercased() == "s3-s1.retailcrm.tech"
            && knownPaths.contains(directory)
            && ["logo_horiz", "logo_horiz_white"].contains(name)
            && ["svg", "png"].contains(url.pathExtension.lowercased())

        if isStandardLogo {
            let resolvedName = theme.isDarkTheme ? "logo_horiz_white" : name
            components.path = directory + resolvedName + ".png"
            return components.url
        }

        // UIImage cannot decode arbitrary remote SVGs; keep the brand name as fallback.
        return url.pathExtension.lowercased() == "svg" ? nil : url
    }

    @discardableResult
    package static func prefetch(
        domainConfig: DomainConfig?,
        theme: ConsultantTheme
    ) -> ImageLoadTask? {
        guard let url = logoURL(domainConfig: domainConfig, theme: theme) else {
            return nil
        }

        return ImageLoader.shared.loadImage(from: url) { _ in }
    }
}
