# Simla iOS SDK

The SDK adds online chat, customer activity tracking, product recommendations, and push notifications to an iOS application.

## Contents

- [Modules](#modules)
- [Requirements](#requirements)
- [Installation](#installation)
    - [SPM](#swift-package-manager)
    - [CocoaPods](#cocoapods)
- [Initialization](#initialization)
- [HTTP observation](#http-observation)
- [Customer identification](#customer-identification)
- [Using modules](#using-modules)
- [Public errors](#public-errors)
- [Local storage](#local-storage)
- [Project checks](#project-checks)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Modules

Swift module / CocoaPods — Purpose

`Core` / `SimlaCore` — Shared runtime and the `CrmSdk` entry point
`OnlineConsultant` / `SimlaOnlineConsultant` — Online chat
`Tracker` / `SimlaTracker` — Customer activity tracking
`Recommendations` / `SimlaRecommendations` — Product recommendations
`PushService` / `SimlaPushService` — Firebase push notifications, with Firebase and delegates managed by the application
`PushNotificationExtension` / `SimlaPushNotificationExtension` — Notification processing in a Notification Service Extension

The modules share the `Core` session.
`Recommendations` uses the shared `Tracker`.
`PushNotificationExtension` does not depend on `Core` and runs in the application extension process.

## Requirements

- iOS 15 or later.
- Online chat requires the Online Consultant module to be enabled in Simla.
- Recommendations require a configured recommendation mechanic in Simla.
- Firebase push notifications require Firebase and APNs to be configured in the application.

## Installation

### Swift Package Manager

In Xcode, select **File → Add Package Dependencies** and enter:

```text
https://github.com/simla-tech/MobileSdkIOS.git
```

Select **Exact Version → 0.1.0** for a specific release or **Branch → main** to install from the branch.

Add `Core` and the required SDK products to your application target.
For example, chat requires `Core` and `OnlineConsultant`.
SPM resolves dependencies of the selected products automatically.
Add the `PushNotificationExtension` product to the Notification Service Extension target.

### CocoaPods

Add the shared configuration to your `Podfile`:

```ruby
source 'https://cdn.cocoapods.org/'
platform :ios, '15.0'
use_frameworks! :linkage => :static

sdk_source = {
  :git => 'https://github.com/simla-tech/MobileSdkIOS.git',
  :branch => 'main'
}
```

This configuration installs the SDK from the `main` branch. To install a specific release, replace `sdk_source` with:

```ruby
sdk_source = {
  :git => 'https://github.com/simla-tech/MobileSdkIOS.git',
  :tag => '0.1.0'
}
```

`Podfile.lock` records the installed commit. To update the SDK from the branch, run `pod update` with the names of the installed `Simla*` pods.

Choose a `target` configuration below. Each example includes all SDK dependencies required by that module.
For multiple modules, combine their lists in one `target`, declaring each pod only once.

#### Online Consultant

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaOnlineConsultant', sdk_source
end
```

#### Tracker

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaTracker', sdk_source
end
```

#### Product recommendations

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaTracker', sdk_source
  pod 'SimlaRecommendations', sdk_source
end
```

#### Push notifications in the application

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaPushNotificationExtension', sdk_source
  pod 'SimlaPushService', sdk_source
end
```

#### Notification Service Extension

```ruby
target 'YourAppNotificationExtension' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaPushNotificationExtension', sdk_source
end
```

Replace the target names with those in your project, run `pod install`, and open the generated
`.xcworkspace`. The extension block is required only when a Notification Service Extension is present.

Direct Git integration also requires listing the internal `SimlaSDKConfiguration` and `SimlaSQLiteStorage` pods with `sdk_source`.
CocoaPods resolves Firebase dependencies from the public specification repository.

## Initialization

Call `CrmSdk.initialize` once when the application starts. Configure the required modules immediately after the call.
Initialization and access to `CrmSdk.shared` must run on the main actor.
`completion` reports the shared session connection result.

UIKit example:

```swift
import Core
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        CrmSdk.initialize(
            config: CrmSdkConfig(siteToken: "<site-token>"),
            customerIdentity: CrmSdkCustomerIdentity(
                customerId: 123,
                siteCustomerId: "customer-123",
                siteCode: "main"
            ),
            pageContext: ConnectPageContext(
                title: "Home",
                url: URL(string: "https://example.com"),
                referURL: URL(string: "https://example.com")
            )
        ) { result in
            switch result {
            case .success:
                print("CrmSdk initialize success")
            case .failure(let error):
                print("CrmSdk initialize failure, error:\n\(error.localizedDescription)")
            }
        }
        self.configureOnlineConsultantChat()
        self.configurePush()
        self.configureTracker()
        self.configureRecommendations()
        return true
    }
}
```

- `config` — required SDK settings. `site-token` is the site token from the Simla online consultant or tracker settings.
- `customerIdentity` — optional customer identity in Simla. Provide `customerId` or `siteCustomerId`; `siteCustomerId` also requires `siteCode`.
- `pageContext` — screen information for the initial connection. `title` is sent as `page_title`, `url` is used to filter tracker events, and `referURL` is sent as `refer_url`. All fields are optional.
- `completion` — required `Result<Void, CoreError>` handler for the initial connection when using the callback variant.

In addition to `siteToken`, `CrmSdkConfig` accepts these optional parameters:

- `baseURL` — HTTP(S) backend URL, default: `https://c.retailcrm.tech`. Accepts a host URL or the full `/api/client/v1` path; trailing slashes are removed. Query and fragment are not allowed. Used by all network modules; WebSocket uses `ws` or `wss`.
- `requestTimeout` — timeout for receiving data in an HTTP request, in seconds. Default: `30`.
- `resourceTimeout` — maximum HTTP request duration, in seconds. Default: `60`.
- `consultantConfig` — chat settings. Created automatically by default.
- `trackerConfig` — tracker settings. Created automatically by default.
- `networkObserver` — optional HTTP request observer. Default: `nil`.

`CrmSdk.initialize(config:customerIdentity:pageContext:) async throws -> CrmSdk` returns the instance after a successful connection. The `completion` variant returns the instance immediately and reports the connection result later.

The SDK starts connecting to the server after initialization. All installed modules use the same `CrmSdk` instance.
SDK modules in the application share a `URLSession`. `PushNotificationExtension` uses its own session.

## HTTP observation

Pass a `CrmSdkNetworkObserver` in `CrmSdkConfig.networkObserver` before initialization to receive events from all application SDK HTTP modules, including `/connect` and resource loading. The default is `nil`.

```swift
import Core
import Foundation

final class NetworkObserver: CrmSdkNetworkObserver {
    var collectsMetrics: Bool { true }

    func requestDidStart(_ event: CrmSdkNetworkRequest) {
        print(event.id, event.request, event.startedAt)
    }

    func requestDidComplete(_ event: CrmSdkNetworkResponse) {
        print(event.id, event.response as Any, event.responseBody as Any,
              event.error as Any, event.duration)
    }

    func requestDidCollectMetrics(_ metrics: URLSessionTaskMetrics, requestID: UUID) {
        print(requestID, metrics)
    }
}

let config = CrmSdkConfig(siteToken: "<site-token>", networkObserver: NetworkObserver())
```

Callbacks run asynchronously on a private serial queue. Start precedes completion for each request; every retry receives a new UUID. `startedAt` is the task creation time; `duration` uses a monotonic clock. Completion describes the transport result before status validation and decoding: HTTP 4xx/5xx alone do not set `error`, while timeouts and cancellation do. `responseBody` contains data-task response bytes; file downloads report `nil` without reading the file into memory.

Metrics are disabled by default. Set `collectsMetrics = true` and implement `requestDidCollectMetrics` to receive system-provided metrics; each request is identified by its UUID. Metrics may arrive before or after completion. WebSocket messages and decoding errors are outside this HTTP interface.

The SDK retains the observer and forwards events without storing request history. Headers and bodies are passed as sent or received; the observer controls redaction and retention. Callback work does not block request completion. Each observer must support access across threads, and callbacks should finish promptly.

`PushNotificationExtension` runs in a separate process. Pass an observer separately using `PushNotificationHandler(siteToken:baseURL:networkObserver:)`; its public observer types are available through `import PushNotificationExtension`.

## Customer identification

If the customer is known at startup, pass `customerIdentity` to `CrmSdk.initialize`.
After sign-in or an account change, call `CrmSdk.shared.setCustomerIdentity(_:) async throws` or the `completion` variant.
The method updates the customer identity and reconnects the shared SDK session so that installed modules work with the current customer.
Wait for successful completion before continuing work with that customer.

```swift
import Core

@MainActor
func identifyCustomer() async throws {
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // Internal Simla customer ID.
            customerId: 37
        )
    )
    
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // Site-side customer ID and Simla site code.
        // Always pass siteCustomerId and siteCode together.
            siteCustomerId: "customer-42",
            siteCode: "main"
        )
    )
    
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // Both identification methods.
        // If a module needs only one identifier,
        // the SDK uses customerId first.
            customerId: 37,
            siteCustomerId: "customer-42",
            siteCode: "main"
        )
    )
}
```

Pass `nil` on sign-out:

```swift
@MainActor
func signOutFromSdk() async throws {
    try await CrmSdk.shared.setCustomerIdentity(nil)
}
```

To link chat to a CRM customer, provide `siteCustomerId` and `siteCode`.
The internal `customerId` alone is insufficient to link chat; it can also be provided for other modules.

Tokens are stored separately for each combination of `siteToken` and `customerIdentity`.
The storage key includes `siteCode`, `siteCustomerId`, and `customerId` if provided.
An anonymous token is stored separately for each `siteToken`.
Connections use only the token for the current identity. If none exists, `/connect` is sent without `user.token`.
The anonymous token is not transferred to an authenticated session.
Guest history is not transferred automatically on sign-in. Returning to a previous identity uses its saved token.

## Using modules

After successful initialization, access the SDK instance through `CrmSdk.shared`.
The `onlineConsultant`, `tracker`, `recommendations`, and `pushService` properties create the corresponding module on first access and return the same instance on subsequent accesses.
Import the corresponding Swift module to access its API.

Module documentation:

- [Online consultant](./onlineConsultant.md) — displaying chat.
- [Tracker](./tracker.md) — sending events.
- [Product recommendations](./recommendations.md) — retrieving recommended products and tracking interactions.
- [Push notifications](./push-firebase.md) — configuring Firebase and registering categories.

## Public errors

Public errors conform to `LocalizedError`.
Messages for predefined states are available in Russian, English, and Spanish.
Diagnostic details and server messages may remain in their original language.

The public error type of `Core` is `CoreError`.

`CrmSdk.initialize` and `CrmSdk.shared.setCustomerIdentity` pass this type to `completion`.

Public `Codable` models in `Core` wrap encoding and decoding errors in `CoreError`.

- `invalidCustomerIdentity(String)` — invalid customer identity; the string contains the reason.
- `missingConnectionCredentials` — the connection response contains no session credentials.
- `httpStatus(Int, [String])` — HTTP status and server messages.
- `keychainInvalidTokenData`, `keychainUnexpectedStatus(Int32)` — invalid stored token or a Keychain error code.
- `requestEncodingFailed(String)`, `responseDecodingFailed(String)` — encoding or decoding failure.
- `requestFailed(String)`, `cancelled` — request failure or cancellation.
- `unexpected(String)` — unexpected operation error.

## Local storage

`SQLiteStorage` is an internal SQLite module with no dependency on `Core`.
`SDKConfiguration` provides shared API endpoints for `Core` and `PushNotificationExtension`.

Separate databases are stored in Application Support:

- `crm_consultant_tracker.sqlite` — Tracker events;
- `crm_push_registration.sqlite` — PushService registration fingerprint and category lists;
- `crm_push_status_retries.sqlite` — push status retry queue.

OnlineConsultant file cache metadata is stored in
`Library/Caches/ConsultantSDK/crm_consultant_cache.sqlite`; attachments remain in the adjacent `files` directory.
Opening the cache removes records for missing files and files without records.
File deletion failures during cleanup are returned to the caller.

The application and extension keep independent queues in their own containers; no App Group is required.
`PushServiceError.storage(String)` reports push registration database access failures.

## Project checks

[GitHub Actions](../../.github/workflows/ci.yml) runs `SPM build` and `Pod build` in parallel.
`Pod build` installs all local pods and builds a temporary application with a Notification Service Extension.
After successful builds, seven test jobs cover the modules and SQLite storage.
Push tests that require a host application are skipped in the current SPM run.

## Contributing

Before creating a pull request:

1. Describe the problem or proposed change.
2. Add tests for changed behavior and run them in iOS Simulator.
3. Verify the SDK build and integration of the affected modules in an application.
4. Update documentation and examples when changing the public API.

## Security

Do not disclose vulnerabilities in public issues.

Use GitHub Private Vulnerability Reporting: Security → Report a vulnerability. If the form is unavailable, contact the maintainers through a private channel first.

## License

The project is distributed under the Apache License 2.0. See [LICENSE](../../LICENSE).
