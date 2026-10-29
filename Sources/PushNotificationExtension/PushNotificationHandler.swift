import Foundation
import SDKConfiguration
import UserNotifications

/// Notification service extension support without initializing the application SDK.
public final class PushNotificationHandler {
    private static let buttonActionURLsUserInfoKey = "push_button_action_urls"

    private let siteToken: String
    private let session: any PushNetworkSession
    private let statusReporter: PushStatusReporter
    private let retryObservation: PushStatusRetryObservation

    /// Receives the current retry queue and future updates for this site, off the main thread.
    /// Includes statuses queued by other handlers in this process. Assign nil to unsubscribe.
    public var onStatusRetryUpdate: ((PushStatusRetryUpdate) -> Void)? {
        get { retryObservation.onUpdate }
        set { retryObservation.onUpdate = newValue }
    }

    /// Uses the same backend URL and site token as the application.
    public convenience init(
        siteToken: String, baseURL: String = SDKBackend.defaultBaseURL,
        networkObserver: (any CrmSdkNetworkObserver)? = nil
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.init(
            siteToken: siteToken, baseURL: baseURL,
            session: URLSession(configuration: configuration), networkObserver: networkObserver
        )
    }

    package init(
        siteToken: String,
        baseURL: String = SDKBackend.defaultBaseURL,
        session: any PushNetworkSession,
        retryQueue: PushStatusRetryQueue = .shared,
        networkObserver: (any CrmSdkNetworkObserver)? = nil
    ) {
        self.siteToken = siteToken
        let observedSession: any PushNetworkSession
        if let networkObserver {
            observedSession = ObservedPushNetworkSession(session: session, observer: networkObserver)
        } else {
            observedSession = session
        }
        self.session = observedSession
        self.statusReporter = .init(
            session: observedSession, retryQueue: retryQueue,
            clientAPIEndpointURL: BackendEndpoints(baseURL: baseURL).clientAPIEndpointURL
        )
        self.retryObservation = .init(siteToken: siteToken, queue: retryQueue)
    }

    /// Reports delivery and enriches a RetailCRM notification with buttons and an optional image attachment.
    ///
    /// Returns false without calling completion for unrelated notifications.
    ///
    /// - Parameters:
    ///   - request: Notification request received by the service extension.
    ///   - content: Mutable notification content to enrich.
    ///   - completion: Receives enriched content only for a handled RetailCRM notification.
    @discardableResult
    public func handle(
        request: UNNotificationRequest,
        content: UNMutableNotificationContent,
        completion: @escaping (UNMutableNotificationContent) -> Void
    ) -> Bool {
        guard let message = PushMessageParser.parse(
            userInfo: request.content.userInfo,
            title: request.content.title,
            body: request.content.body
        ) else {
            return false
        }

        var userInfo = content.userInfo
        userInfo[PushNotificationMetadata.deliveredByExtensionUserInfoKey] = true
        content.userInfo = userInfo

        let group = DispatchGroup()
        group.enter()
        statusReporter.reportStatus(.delivered, pushId: message.pushId, siteToken: siteToken) { _ in
            group.leave()
        }

        group.enter()
        applyButtons(from: message, to: content) {
            guard let imageURL = message.imageURL else {
                group.leave()
                return
            }

            self.downloadImageAttachment(from: imageURL) { attachment in
                if let attachment {
                    content.attachments = [attachment]
                }
                group.leave()
            }
        }

        group.notify(queue: DispatchQueue.main) {
            completion(content)
        }

        return true
    }

    private func downloadImageAttachment(
        from imageURL: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        session.downloadTask(with: imageURL) { temporaryURL, response, _ in
            guard let temporaryURL else {
                completion(nil)
                return
            }

            let fileExtension = self.fileExtension(for: imageURL, response: response)
            let localURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: localURL)
                completion(try UNNotificationAttachment(identifier: "image", url: localURL))
            } catch {
                completion(nil)
            }
        }
        .resume()
    }

    private func applyButtons(
        from message: PushMessage,
        to content: UNMutableNotificationContent,
        completion: @escaping () -> Void
    ) {
        let buttons = message.buttons
        guard !buttons.isEmpty else {
            if let categoryIdentifier = message.rgCategory {
                content.categoryIdentifier = categoryIdentifier
            }
            completion()
            return
        }

        let categoryIdentifier = message.pushId

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: buttons.enumerated().map { index, button in
                UNNotificationAction(
                    identifier: Self.actionIdentifier(categoryIdentifier: categoryIdentifier, index: index),
                    title: button.title,
                    options: [.foreground]
                )
            },
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        content.categoryIdentifier = categoryIdentifier
        var userInfo = content.userInfo
        userInfo[Self.buttonActionURLsUserInfoKey] = Dictionary(
            uniqueKeysWithValues: buttons.enumerated().map { index, button in
                (Self.actionIdentifier(categoryIdentifier: categoryIdentifier, index: index), button.value)
            }
        )
        content.userInfo = userInfo

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            var updatedCategories = categories.filter {
                $0.identifier != categoryIdentifier
            }
            updatedCategories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updatedCategories)
            completion()
        }
    }

    private static func actionIdentifier(categoryIdentifier: String, index: Int) -> String {
        "\(categoryIdentifier)_\(index)"
    }

    private func fileExtension(for url: URL, response: URLResponse?) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif"].contains(pathExtension) {
            return pathExtension
        }

        switch response?.mimeType?.lowercased() {
        case "image/jpeg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        default:
            return "jpg"
        }
    }
}
