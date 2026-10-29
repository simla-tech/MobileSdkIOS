import Core
import CryptoKit
import PushNotificationExtension
import Foundation
import UserNotifications

package enum PushNotificationHandlingResult {
    case handled(PushMessage)
    case notHandled
}

package final class PushHandler {
    private let siteToken: String
    private let statusReporter: PushStatusReporter
    private let retryObservation: PushStatusRetryObservation

    package var onStatusRetryUpdate: ((PushStatusRetryUpdate) -> Void)? {
        get { retryObservation.onUpdate }
        set { retryObservation.onUpdate = newValue }
    }

    package init(
        siteToken: String,
        clientAPIEndpointURL: URL = APIEndpoints().clientAPIEndpointURL,
        session: URLSession = NetworkSession.shared,
        retryQueue: PushStatusRetryQueue = .shared
    ) {
        let networkSession = PushAppNetworkSession(session: session)
        self.siteToken = siteToken
        self.statusReporter = .init(
            session: networkSession, retryQueue: retryQueue, clientAPIEndpointURL: clientAPIEndpointURL
        )
        self.retryObservation = .init(siteToken: siteToken, queue: retryQueue)
    }

    @discardableResult
    package func handleSilentNotification(
        _ userInfo: [AnyHashable: Any],
        completion: @escaping (Result<Void, PushStatusReportingError>) -> Void
    ) -> Bool {
        guard let message = PushMessageParser.parseSilent(userInfo: userInfo) else {
            return false
        }
        statusReporter.reportStatus(
            .delivered,
            pushId: message.pushId,
            siteToken: siteToken,
            completion: completion
        )
        return true
    }

    @discardableResult
    package func handleWillPresent(
        _ notification: UNNotification,
        completion: @escaping (Result<Void, PushStatusReportingError>) -> Void
    ) -> Bool {
        switch handle(
            status: .delivered,
            content: notification.request.content,
            completion: completion
        ) {
        case .handled:
            return true
        case .notHandled:
            return false
        }
    }

    @discardableResult
    package func handleDidReceive(
        _ response: UNNotificationResponse,
        completion: @escaping (Result<Void, PushStatusReportingError>) -> Void
    ) -> PushNotificationHandlingResult {
        handle(
            status: response.actionIdentifier == UNNotificationDismissActionIdentifier ? .swiped : .clicked,
            actionIdentifier: response.actionIdentifier,
            content: response.notification.request.content,
            completion: completion
        )
    }

    package func actionURLString(in message: PushMessage, for actionIdentifier: String) -> String? {
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            return message.clickAction?.stringUrl
        }
        return button(in: message, for: actionIdentifier)?.value
    }

    private func handle(
        status: PushNotificationStatus,
        actionIdentifier: String? = nil,
        content: UNNotificationContent,
        completion: @escaping (Result<Void, PushStatusReportingError>) -> Void
    ) -> PushNotificationHandlingResult {
        guard let message = PushMessageParser.parse(
            userInfo: content.userInfo,
            title: content.title,
            body: content.body
        ) else {
            return .notHandled
        }

        if status == .delivered,
           content.userInfo[PushNotificationMetadata.deliveredByExtensionUserInfoKey] as? Bool == true
        {
            completion(.success(()))
            return .handled(message)
        }

        statusReporter.reportStatus(
            status,
            pushId: message.pushId,
            buttonHash: {
                if status == .clicked,
                   let actionIdentifier,
                   let button = button(in: message, for: actionIdentifier)
                {
                    return button.hash
                }
                return nil
            }(),
            siteToken: siteToken,
            completion: completion
        )
        return .handled(message)
    }

    private func button(in message: PushMessage, for actionIdentifier: String) -> PushButton? {
        guard
            let indexString = actionIdentifier.components(separatedBy: "_").last,
            let index = Int(indexString),
            index >= 0 && message.buttons.count > index,
            actionIdentifier == Self.actionIdentifier(categoryIdentifier: message.pushId, index: index)
        else { return nil }
        return message.buttons[index]
    }

    private static func actionIdentifier(categoryIdentifier: String, index: Int) -> String {
        "\(categoryIdentifier)_\(index)"
    }
}

private extension PushButton {
    var hash: String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
