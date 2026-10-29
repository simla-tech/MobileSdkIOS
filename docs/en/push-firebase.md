# Push notifications through Firebase

The `push-firebase` module integrates Simla push notifications through Firebase Cloud Messaging: device registration, notification display, and status reporting.

## Contents

- [Allowing Simla to send notifications](#allowing-simla-to-send-notifications)
- [Setup](#setup)
- [Customer identification](#customer-identification)
- [Providing a device token](#providing-a-device-token)
- [Registering a push token and categories](#registering-a-push-token-and-categories)
- [Handling notifications](#handling-notifications)
- [Handling notifications when the application is in the background or closed](#handling-notifications-when-the-application-is-in-the-background-or-closed)
- [Navigation and notification data](#navigation-and-notification-data)
- [Public methods and properties](#public-methods-and-properties)
- [Push notification analytics](#push-notification-analytics)
- [Public errors](#public-errors)
- [AppDelegate implementation example](#appdelegate-implementation-example)

## Allowing Simla to send notifications

To allow Simla to send notifications through your Firebase project, grant the Simla service account access to the Firebase Cloud Messaging API.
Firebase [supports](https://firebase.google.com/docs/cloud-messaging/send/v1-api#authorize_a_service_account_from_a_different_project) sending messages using a service account from another project.

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select the project connected to your iOS application.

2. Go to **IAM & Admin → IAM** and click **Grant access**.

3. In **New principals**, enter the Simla service account:

   ```text
   firebase-adminsdk-fbsvc@push-service-sender.iam.gserviceaccount.com
   ```

4. Assign the **Firebase Cloud Messaging API Admin** role (`roles/firebasecloudmessaging.admin`).

5. Click **Save**.

This role permits sending messages through your project's FCM API.
See the [role description in the Firebase documentation](https://firebase.google.com/docs/projects/iam/roles-predefined-product#cloud-messaging-roles).

## Setup

Configure Firebase in the application using the [Firebase instructions](https://firebase.google.com/docs/ios/setup).

Call `configurePush()` immediately after `CrmSdk.initialize(...)`. Registration waits for the session and token.

```swift

import Core
import PushService

CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>"
    )
) { result in
    if case .failure(let error) = result {
        print(error.localizedDescription)
    }
}
configurePush()

private func configurePush() {
    let pushService = CrmSdk.shared.pushService
    pushService.onPushRegistrationResult = { result in
        switch result {
        case .success(let token):
            print("Push registration succeeded; token: \(token)")
        case .failure(let error):
            print("Push registration failed: \(error.localizedDescription)")
        }
    }
}
```

The application configures Firebase, obtains an FCM token or Firebase Installation ID, registers with APNs, and assigns notification delegates.

Firebase must be configured before all conditions for applying the subscription are met.
To register a token, the SDK reads the Firebase project ID from `FirebaseApp.app()?.options.projectID`.

## Customer identification

Notify the SDK of sign-in, account changes, and sign-out through `CrmSdk.shared.setCustomerIdentity(...)`.
See [Customer identification](./sdk.md#customer-identification).

## Providing a device token

Pass the device token through `setToken(_:)`. For FCM, assign `Messaging.messaging().delegate = self` in `AppDelegate` after configuring Firebase and calling `CrmSdk.initialize`.
Use the appropriate token retrieval variant:

```swift
import UIKit
import Core
import PushService
import FirebaseMessaging
import FirebaseInstallations

// When using FCM
extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            CrmSdk.shared.pushService.setToken(.fcm(fcmToken))
        }
    }
}

// When using FID
extension AppDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken

        Messaging.messaging().register { error in
            guard error == nil else {
                // Handle the registration error.
                return
            }

            Installations.installations().installationID { installationId, error in
                guard error == nil, let installationId else {
                    // Handle the FID retrieval error.
                    return
                }
                Task { @MainActor in
                    CrmSdk.shared.pushService.setToken(.fid(installationId))
                }
            }
        }
    }
}
```

Instead of `pushService.setToken()`, you can call `pushService.setDeviceToken(_:completion:)` to have the SDK obtain an FCM token or Firebase Installation ID through Firebase.
The method assigns `Messaging.messaging().apnsToken = deviceToken`.
If Firebase Installation ID is enabled, the SDK calls `Messaging.messaging().register(...)` and retrieves the FID through `Installations.installations().installationID(...)`; otherwise, it requests an FCM token through `Messaging.messaging().token(...)`.

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    CrmSdk.shared.pushService.setDeviceToken(deviceToken) { result in
        switch result {
        case .success(let token):
            print("Token: \(token)")
        case .failure(let error):
            print("Failed to retrieve the token: \(error)")
        }
    }
}
```

Differences between the methods:

- `setToken` stores the supplied value in memory and starts applying the subscription when categories and the session are ready.
- `setDeviceToken` additionally passes the APNs token to Firebase and retrieves an FCM token or FID, which it then uses for registration.

When using only `setToken`, the application is responsible for configuring Firebase, registering with APNs, and associating the APNs token with Firebase.
For FID, the application must also perform Firebase Messaging registration, which the SDK calls in `setDeviceToken`.

## Registering a push token and categories

Use `registerNotificationCategories(_:completion:)` to register a push token and CRM notification categories.

The method performs the following steps:

1. Removes duplicates and sorts codes: `["news", "sale", "news"]` becomes `["news", "sale"]`.
2. Immediately stores the desired list in memory and UserDefaults. The confirmed list and parameter fingerprint are saved in `UserDefaults` after a successful server response, separately for each `siteToken`. The fingerprint includes the token, customer identifiers, Firebase project, and categories. Matching parameters prevent duplicate requests, including after an application restart. This check applies to registration and unsubscription; category order and duplicate codes do not affect comparison.
3. Updates categories in `UNUserNotificationCenter`: creates categories with the same identifiers, no buttons, and `.customDismissAction` to handle dismissals. Previously SDK-managed categories absent from the new list are removed. Other application categories are preserved, but a matching identifier causes the category to be replaced.
4. Waits for a valid push token and a connected session with a customer identifier, then checks the Firebase project ID.
5. Sends the category list, token, and customer identifiers to the server. If a different list arrives before the request starts, the previous pending call completes with `PushServiceError.operationSuperseded`.

The application maintains the current CRM notification category list and passes it on every launch and subscription change.
Pass `[]` to disable subscriptions, or the desired categories to enable them.
The SDK applies the current category list when the token, categories, or session state changes.
Automatic registration does not occur until the first `registerNotificationCategories` call in the current run.

On failure, the supplied list and local categories are retained; the confirmed list remains unchanged.
Before sending a new request, the previous fingerprint is cleared: the server may have processed a request even if it returned an error.
There are no timer-based retries: another attempt can occur on a new token or session event, or another call to `registerNotificationCategories`.

On the main thread, assign a result handler and supply the current category list and token.
The SDK performs registration automatically.
The method saves data on the Online Consultant backend.
The backend transfers registered tokens and categories to Simla through a background job at the start of each hour.
A subscription or unsubscription therefore usually takes effect after the next successful synchronization, approximately within 60 minutes of the method call.
Transfer errors may cause a longer delay.

```swift
import Foundation
import Core
import PushService

let pushService = CrmSdk.shared.pushService
pushService.onPushRegistrationResult = { result in
    if case let .failure(error) = result {
        print("Failed to update the push subscription: \(error)")
    }
}
let availableCRMCategories = ["crm-category"]
pushService.registerNotificationCategories(availableCRMCategories) { result in
    if case let .failure(error) = result, error != .operationSuperseded {
        print("Failed to apply notification categories: \(error)")
    }
}
```

## Handling notifications

Implement the `UNUserNotificationCenterDelegate` methods and pass notifications to the service.
If a notification is recognized as a CRM notification, the SDK calls the system `completionHandler`.

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
    if CrmSdk.shared.pushService.handleWillPresent(
        notification,
        withCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        // The notification was recognized as a CRM notification and handled by the SDK
        return
    }
    // Handle other notifications in the application.
    completionHandler([.banner, .badge, .sound])
}

func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    if CrmSdk.shared.pushService.handleDidReceive(
        response,
        withCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        // The notification was recognized as a CRM notification and handled by the SDK
        return
    }
    // Handle other notifications in the application.
    completionHandler()
}
```

For silent notifications, enable Background Modes → Remote notifications.
Add the following to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
<string>remote-notification</string>
</array>
```

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    if CrmSdk.shared.pushService.handleSilentNotification(
        userInfo,
        fetchCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        return
    }

    // Handle other notifications in the application.
    completionHandler(.noData)
}
```

## Handling notifications when the application is in the background or closed

iOS can deliver and display a regular visible push notification without a Notification Service Extension.
To let the SDK report `.delivered` and add buttons or an image before display, add a **Notification Service Extension**.

In Xcode, select **File → New → Target → Notification Service Extension**.
Add the `PushNotificationExtension` product to the extension target and use `PushNotificationHandler` with the same `siteToken` and `baseURL` as the application. `baseURL` is optional and defaults to `https://c.retailcrm.tech`:

```swift
import UserNotifications
import PushNotificationExtension

final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var originalContent: UNNotificationContent?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var didComplete = false

    private let pushHandler = PushNotificationHandler(
        siteToken: "<siteToken>"
    )

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        DispatchQueue.main.async {
            self.contentHandler = contentHandler
            self.originalContent = request.content

            guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
                self.complete()
                return
            }

            self.bestAttemptContent = content
            if self.pushHandler.handle(request: request, content: content, completion: { [weak self] content in
                guard let self, !self.didComplete else { return }
                self.bestAttemptContent = content
                self.complete()
            }) {
                return
            }
            // Handle notifications from other senders in the application.
            self.complete()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        complete()
    }

    private func complete() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.complete()
            }
            return
        }

        guard !didComplete else {
            return
        }

        didComplete = true
        let contentHandler = self.contentHandler
        self.contentHandler = nil
        if let bestAttemptContent {
            contentHandler?(bestAttemptContent)
        } else if let originalContent {
            contentHandler?(originalContent)
        }
    }
}
```

The optional `networkObserver` initializer parameter receives extension HTTP events independently of the application observer. See [HTTP observation](./sdk.md#http-observation).

### Public methods of `PushNotificationHandler`

- `init(siteToken: String)` — creates a handler with the same `siteToken` used by the application.
- `handle(request:content:completion:) -> Bool` — reports `.delivered` and adds buttons and an image. Marks the content to prevent the application from reporting the status again. Calls `completion` on the main thread after status reporting and processing finish.

Returns `false` for notifications from other senders without reporting a status or calling `completion`.
Call the system `contentHandler` exactly once, in `completion` or `serviceExtensionTimeWillExpire()`.

The `PushNotificationExtension` module does not depend on `Core`, Firebase, or other SDK modules.
It uses its own `URLSession`: `30` seconds for receiving data and `60` seconds for the entire HTTP request.

## Navigation and notification data

The following fields are configured in Simla when setting up a push notification and passed to the SDK in the notification's `userInfo`:

| Field | Purpose |
|-------|---------|
| `click_action` | Navigation URL or string action identifier |
| `ca_<key>` | Custom attributes for notification handling by the application |
| `image_url` | URL of an image added to the notification |
| `buttons` | JSON array of up to two buttons with `title` and `value` fields |

Displaying images and buttons requires a Notification Service Extension with the SDK handler.

`click_action` behavior:

For `"myapp://orders/123"`, the SDK passes the string to `onNotificationOpen` through `NotificationAction.urlString`. The application handles navigation.
If the field is absent, the SDK uses `url` or `link` when provided. If all three fields are absent, `NotificationAction.urlString` is `nil`, but the open handler is still called.

When a button is tapped, the SDK passes its `value` in `NotificationAction.urlString` instead of `click_action`. Dismissing a notification does not call `onNotificationOpen`.

`ca_*` fields are passed to the application through `NotificationAction.customAttributes`. The `ca_` prefix is removed from keys. String values remain unchanged; numeric values are converted to strings.

In the current implementation, `customAttributes` are passed only when a nonempty `click_action`, `url`, or `link` is present.

For example, given these custom notification fields:

```json
{
    "click_action": "OPEN_ORDER",
    "ca_orderId": "123"
}
```

In the application:

```swift
pushService.onNotificationOpen = { action in
    // The click_action value or the value of the tapped button.
    let actionValue = action.urlString // "OPEN_ORDER"
    // The ca_orderId field is provided under the orderId key.
    let orderId = action.customAttributes?["orderId"] // "123"
    // Navigate to the appropriate application screen.
}
```

## Public methods and properties

`CrmSdk.shared.pushService` returns `PushService`.

- `onStatusRetryUpdate: ((PushStatusRetryUpdate) -> Void)?` — reports queued push statuses, retry requests, scheduled attempts, success, and retry termination off the main thread. Assignment emits `pending` snapshots for existing entries of the current site. Initial requests that never enter the retry queue are not published. Assign `nil` to unsubscribe. Events and their parameters are described in [Push notification analytics](#push-notification-analytics).
- `onPushRegistrationResult: ((Result<PushToken, PushServiceError>) -> Void)?` — reports registration or unsubscription results on the main thread, including parameter validation errors. The event is not emitted when assigning the handler, skipping an already confirmed state, or replacing a pending call with `operationSuperseded`. Success confirms server acceptance of the parameters, not notification delivery.
- `registerNotificationCategories(_:)` accepts the complete desired list of CRM category codes. Call it on every application launch and subscription change. An empty list `[]` unsubscribes from all categories. The SDK waits for a valid token and a connected session with a customer identifier; it checks the Firebase project ID before sending. The SDK registers matching iOS categories with `.customDismissAction` and removes previously managed categories absent from the new list. Other application categories are preserved. If a code matches an application category, the SDK replaces that category and its actions. Use distinct codes. Removing an iOS category does not block notification delivery or change system authorization. The method is available as `async throws -> PushToken` and with `completion: (Result<PushToken, PushServiceError>) -> Void`. It returns after local categories are updated and the server accepts the parameters, a saved confirmation is used, or an error occurs.
- `setToken(_ token: PushToken)` — accepts `.fcm(String)` or `.fid(String)`.
- `setDeviceToken(_:) async throws -> PushToken` and the `completion` variant — accept an APNs token and obtain an FCM token or Firebase Installation ID through Firebase.
- `handleWillPresent(_:withCompletionHandler:completion:) -> Bool` — reports `.delivered` for a notification received while the application is open.
- `handleDidReceive(_:withCompletionHandler:completion:) -> Bool` — reports `.clicked` or `.swiped` for a user action.
- `onNotificationOpen: ((NotificationAction) -> Void)?` — passes the original navigation string (`urlString`) to the application. Tapping the notification provides the navigation link and custom attributes if specified. Tapping a button provides only the navigation link. The SDK does not open the link.
- `handleSilentNotification(_:fetchCompletionHandler:completion:) -> Bool` — reports `.delivered` for a silent Simla notification.
- `PushService.version: String` — module version.

Notification handling methods return `true` if the notification is recognized as a Simla notification.
In that case, the SDK invokes the supplied system completion handler itself.
On `false`, the application handles the notification and invokes the handler itself.
The `completion` parameter receives `Result<Void, PushServiceError>` only for recognized notifications.

## Push notification analytics

The SDK automatically reports notification interaction statuses:

| Event | Status |
|-------|--------|
| Notification received | `delivered` |
| Notification or button tapped | `clicked` |
| Notification dismissed | `swiped` |

Network failures, invalid HTTP responses, and HTTP `408`, `425`, `429`, and `5xx` responses are saved
for automatic retry. There are up to five total attempts with delays of `10`, `20`, `40`, and `80`
seconds; `Retry-After` may extend the delay. The original `changed_at` and `button_hash` are preserved.
Other HTTP errors and encoding failures are not retried.

Queue entries are serialized as JSON in `UserDefaults.standard`, separately for the application
and notification extension. Retries run while the respective process is active and the network is
available. After termination, the queue resumes when
`PushService` or `PushNotificationHandler` is created in that process. iOS does not guarantee retries
while the application is suspended or the extension has terminated.

`completion` is called once with the first attempt's result, after a transient failure is saved to
the queue. Later retries do not delay notification processing completion.

To observe retries, assign `CrmSdk.shared.pushService.onStatusRetryUpdate`.
The extension exposes `PushNotificationHandler.onStatusRetryUpdate`:

```swift
CrmSdk.shared.pushService.onStatusRetryUpdate = { update in
    print("Push status retry:", update)
}
```

The handler receives `PushStatusRetryUpdate` off the main thread. Assignment emits `pending` snapshots
for existing entries of the current site, followed by future changes. Assign `nil` to unsubscribe.
Handlers on separate instances are independent; the application and extension observe their own queues.

| Event | Meaning |
|-------|---------|
| `pending` | Existing entry, started attempt count, and next attempt time |
| `queued` | Status saved after its first transient failure, including the error |
| `sending` | A retry request is starting; its number includes the initial attempt |
| `retryScheduled` | Next attempt number, scheduled time, and error |
| `delivered` | Backend accepted the status, including a separate successful report of the same status |
| `rejected` | A permanent error ended retries |
| `dropped` | Attempt limit reached; the last error may be unavailable after process interruption |

Each update includes a `PushStatusRetryEvent`: stable entry `id`, `pushID`, `status`, original
`changedAt`, and `buttonHash`. `siteToken` is omitted. Initial requests that never enter the retry
queue are not published. `delivered` means the backend accepted the status, not that the notification
itself reached the device.

## Public errors

Public errors conform to `LocalizedError`.
Messages for predefined states are available in Russian, English, and Spanish.
Diagnostic details and server messages may remain in their original language.

The public error type of `PushService` is `PushServiceError`.

Public `PushService` operations pass this type to `completion`. Denial of notification authorization returns `authorizationDenied`. Notification status reporting failures arrive as `statusReporting(...)` in notification handlers.

- `invalidCustomerIdentity(String)`, `missingCustomerIdentifier` — invalid or missing customer identity.
- `authorizationDenied` — the user denied notification authorization.
- `operationSuperseded` — a pending call was replaced by another category list before the request started.
- `emptyPushToken` — the push token is missing; `registerNotificationCategories` waits for it to become available before sending.
- `emptyFCMToken`, `emptyFID`, `firebaseMessaging(Error)`, `firebaseInstallations(Error)`, `emptyFirebaseProjectID`, `firebaseInstallationIDDisabled` — token retrieval and Firebase configuration errors.
- `invalidHTTPResponse(String)`, `requestEncodingFailed(String)`, `requestFailed(String)`, `httpStatus(Int, [String])` — server token registration errors.
- `statusReporting(StatusReportingFailure)` — status reporting failure: `requestEncodingFailed(String)`, `invalidHTTPResponse(String)`, `requestFailed(String)`, or `httpStatus(Int, [String])`.

## AppDelegate implementation example

This example starts the SDK without a customer identity. After the customer signs in, call `CrmSdk.shared.setCustomerIdentity(_:)` and wait for successful completion.
Provide `customerId`, or `siteCustomerId` together with `siteCode`.
Until a customer identifier is supplied, push subscription registration waits for session readiness.
See [Customer identification](./sdk.md#customer-identification).

```swift
import UIKit
import Core
import FirebaseCore
import PushService

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.configureServices(application)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        CrmSdk.shared.pushService.setDeviceToken(deviceToken) { result in
            switch result {
            case .success(let token):
                print("Token: \(token)")
            case .failure(let error):
                print("Failed to retrieve the token: \(error)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if CrmSdk.shared.pushService.handleSilentNotification(
            userInfo,
            fetchCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Handle other notifications in the application.
        completionHandler(.noData)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    private func configureServices(_ application: UIApplication) {
        self.firebaseConfigure()
        self.registerNootificationCenter(application)
        self.configureCrmSdk()
    }

    private func firebaseConfigure() {
        FirebaseApp.configure()
    }

    private func registerNootificationCenter( _ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Authorization request error: \(error)")
            }
            print("Notification authorization: \(granted)")
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    private func configureCrmSdk() {
        CrmSdk.initialize(
            config: CrmSdkConfig(siteToken: Constants.consultantSiteToken)
//            customerIdentity: .init(customerId: nil, siteCustomerId: nil, siteCode: Constants.siteCode)
        ) { result in
            if case .failure(let error) = result {
                print("CrmSdk initialize failure, error:\n\(error.localizedDescription)")
            }
        }
        self.configurePush()
    }
}

// configure Push
private extension AppDelegate {

    private func configurePush() {
        let pushService = CrmSdk.shared.pushService
        pushService.onPushRegistrationResult = { result in
            switch result {
            case .success(let token):
                print("Push registration succeeded; token: \(token)")
            case .failure(let error):
                print("Push registration failed: \(error.localizedDescription)")
            }
        }
        pushService.onNotificationOpen = { action in
            let url = action.urlString
            let attributes = action.customAttributes
            // Handle taps
        }
        pushService.registerNotificationCategories(Constants.pushCategories) { result in
            if case let .failure(error) = result, error != .operationSuperseded {
                print("Could not apply push categories: \(error.localizedDescription)")
            }
        }
    }
}

// UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if CrmSdk.shared.pushService.handleWillPresent(
            notification,
            withCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Handle other notifications in the application.
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if CrmSdk.shared.pushService.handleDidReceive(
            response,
            withCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Handle the application notification.
        completionHandler()
    }
}

```
