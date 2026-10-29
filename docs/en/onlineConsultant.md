# Online consultant

The `OnlineConsultant` module provides a ready-made chat screen for communication between customers and managers of a CRM system registered with Simla.
The screen is available for UIKit and SwiftUI.

## Contents

- [Setup](#setup)
- [Customer identification](#customer-identification)
- [UIKit](#uikit)
- [SwiftUI](#swiftui)
- [Public methods and properties](#public-methods-and-properties)
- [Real-time events](#real-time-events)
- [Localization](#localization)
- [Chat features](#chat-features)
- [Public errors](#public-errors)

## Setup

Pass chat settings when initializing the SDK:

```swift
CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>",
        consultantConfig: OnlineConsultantConfig(
            connectTimeout: 30,
            autoReconnectWebSocket: true,
            webSocketReconnectDelay: 3,
            messagesPageSize: 50,
            initialMessagesLimit: 50,
            cachePolicy: OnlineConsultantCachePolicy(
                maxDiskSizeBytes: nil,
                maxFileAge: nil,
                automaticCleanup: true
            )
        )
    )
) { result in
    if case let .failure(error) = result { print(error) }
}
```

### Configuring `OnlineConsultantConfig`

- `connectTimeout` — WebSocket connection timeout, in seconds. Default: `30`.
- `autoReconnectWebSocket` — reconnects the WebSocket after an error. Default: `true`.
- `webSocketReconnectDelay` — delay before reconnecting, in seconds. Default: `3`.
- `messagesPageSize` — message history page size; clamped to `1...1000` for requests. Default: `50`.
- `initialMessagesLimit` — target number of messages after the initial connection; range: `0...1000`. Default: `50`.
- `cachePolicy` — file and image cache cleanup policy. Default: `OnlineConsultantCachePolicy()`.

### Configuring `OnlineConsultantCachePolicy`

- `maxDiskSizeBytes: Int64?` — maximum cache size in bytes; `nil` disables the limit.
- `maxFileAge: TimeInterval?` — maximum file age in seconds; `nil` disables the limit.
- `automaticCleanup: Bool` — applies cleanup rules after saving or loading a file; default: `true`. If both limits are `nil`, files are not removed based on size or age. If `false`, run cleanup through `trimCache()` or `clearCache()`, or their `completion` variants.

If `consultantConfig` is omitted, `OnlineConsultantConfig()` is used with a default `connectTimeout` of 30 seconds.

## Customer identification

The application must notify the SDK of sign-in, account changes, and sign-out through `CrmSdk.shared.setCustomerIdentity(_:)`.
To link chat to a CRM customer, provide `siteCustomerId` and `siteCode`.
The internal `customerId` alone is insufficient to link chat.
The SDK does not monitor application authentication automatically.
See [Customer identification](./sdk.md#customer-identification).

When a new identity is supplied, the SDK disconnects the current session and automatically connects a session for the specified customer. There is no need to reconnect chat separately.

On sign-out, call `sdk.setCustomerIdentity(nil)` to notify the SDK and switch to an anonymous session.

## UIKit

The screen uses `CrmSdk.shared.onlineConsultant`.
No additional call is needed to start chat.
To display the chat title, wrapping the screen in a `UINavigationController` is recommended.

```swift
import OnlineConsultant
import UIKit
import Core

func configureOnlineConsultantChat() -> UINavigationController {
    let chatVC = OnlineConsultantViewController()
    let nvChat = UINavigationController(rootViewController: chatVC)
    
    CrmSdk.shared.onlineConsultant.onUnreadIncomingMessagesCountChange = { count in
        // update badge
    }
    CrmSdk.shared.onlineConsultant.onStateChange = { state in
        // update visibility
    }
    return nvChat
}
```

The SDK supports anonymous chat: after connecting without `customerIdentity`, the controller returns `.ready(isAnonymous: true)`. A value of `false` means that an identity is set, but does not confirm a link to a CRM customer record.
Example of restricting chat to sessions with an identity:

```swift
CrmSdk.shared.onlineConsultant.onStateChange = { [weak self] state in
    if case .ready(isAnonymous: false) = state {
        self?.chatTabBarItem.isEnabled = true
    } else {
        self?.chatTabBarItem.isEnabled = false
    }
}
```

## SwiftUI

For the SwiftUI title and badge, create an `OnlineConsultantObserver` and retain it as a `@StateObject`:

```swift
import Core
import OnlineConsultant
import SwiftUI

@MainActor
struct ChatTabView: View {
    @StateObject private var consultant = OnlineConsultantObserver(
        onlineConsultant: CrmSdk.shared.onlineConsultant
    )

    var body: some View {
        TabView {
            OnlineConsultantScreen()
                .tabItem {
                    Label(consultant.name ?? "Chat", systemImage: "bubble.left")
                }
                .badge(consultant.unreadIncomingMessagesCount)
        }
    }
}
```

## Public methods and properties

`CrmSdk.shared.onlineConsultant` returns `OnlineConsultantController`. Its public methods are:

- `cacheStatistics() -> ConsultantCacheStatistics` — returns the file count and local cache size in bytes.
- `trimCache() async throws -> ConsultantCacheStatistics` and the `completion` variant — apply `cachePolicy`.
- `clearCache() async throws` and the `completion` variant — remove files from the SDK's local cache.
- `onStateChange: ((ControllerState) -> Void)?`
- `onUnreadIncomingMessagesCountChange: ((Int) -> Void)?`

Read-only controller properties:

- `state: ControllerState` — current chat state:
  - `.idle` — chat is inactive and is not connecting;
  - `.connecting` — chat is establishing a server connection;
  - `.ready(isAnonymous: Bool)` — chat is connected; `isAnonymous` indicates that the session was created without `customerIdentity`;
  - `.failed(ConsultantError)` — connection failed; reasons are grouped into `.client`, `.controller`, `.fileCache`, and `.attachment`.
- `unreadIncomingMessagesCount: Int` — number of unread incoming messages in the loaded history; `0` if the counter is disabled by configuration.
- `name: String?` — chat title from the server configuration.
- `linkSettings: LinkSettings` — link settings from the server configuration: `links`, `linksMode`, `linksOrientation`, `alwaysShowLinksOnDesktops`.

All public methods and variables of `OnlineConsultantController` are available through `OnlineConsultantObserver` for use in SwiftUI.

## Real-time events

When the online consultant is initialized, the SDK automatically subscribes to events through WebSocket.
New messages and chat state changes appear without additional application actions.

The subscription follows the application lifecycle: the SDK disconnects from WebSocket when the application enters the background and automatically reconnects and subscribes again when it returns to the foreground.
In applications with multiple windows, the connection remains active while at least one window is in the foreground.
A temporary loss of activity without entering the background does not close the connection.
If the session connects in the background, opening the WebSocket is deferred until the application returns to the foreground.

Restoration after backgrounding is independent of `autoReconnectWebSocket` and does not wait for `webSocketReconnectDelay`; those settings control retries after errors in the foreground.
After the session is disconnected, returning to the foreground does not open a WebSocket until a new connection is established.

## Localization

The SDK includes Russian, English, and Spanish translations. iOS selects the language using the application's language settings and the SDK's available localizations. The default language is Russian.

## Chat features

The screen automatically loads history, receives new messages, and sends text.
The attachment button opens the system file and photo picker and supports sending multiple files.

The provided interface supports:

- text messages, links, and quotes;
- images and file attachments;
- product and order cards;
- quick replies;
- contact information forms;
- a contact form when the consultant is offline;
- message sending status;
- retrying failed text, file, and image messages through “Retry sending” in the message context menu;
- loading earlier messages when scrolling through history.

Contact forms, offline mode, and chat appearance follow the online consultant settings received from the server.

The SDK automatically maintains the WebSocket connection while the application is in the foreground and restores it after returning from the background.

## Public errors

Public errors conform to `LocalizedError`.
Messages for predefined states are available in Russian, English, and Spanish.
Diagnostic details and server messages may remain in their original language.

The public error type of `OnlineConsultant` is `ConsultantError`.
`trimCache` and `clearCache` throw it in `async throws` variants or pass it to `completion`.
Connection errors arrive as `ControllerState.failed(ConsultantError)`; state changes are available through `onStateChange`.
Use `localizedDescription` for the error text, or inspect the corresponding `ConsultantError` case and nested `Failure` type to determine the cause.

### Network client errors — `client(ClientFailure)`

- `client(.missingConnectionCredentials)` — the connection response lacks a user token or session ID. The SDK cannot use this connection for chat requests.
- `client(.httpStatus(Int, [String]))` — the server returned an error HTTP status. The first value is the status code and the second contains server messages; the array may be empty.
- `client(.requestFailed(String))` — the request failed or the response could not be parsed correctly. Causes include network, request encoding, or response decoding errors; the string contains details.

### Chat state errors — `controller(ControllerFailure)`

- `controller(.notConnected)` — the operation requires a connected session, but the controller has no user token or session ID. Occurs before connection or after a session reset.
- `controller(.missingCredentials)` — no user token or session ID was found when applying connection data. Unlike `notConnected`, this error concerns received connection data.
- `controller(.unavailable)` — the server returned `behaviour.widget = false`: online chat is unavailable for this connection. This does not mean that no managers are online; offline chat mode is handled separately.
- `controller(.missingUploadedFileID)` — the server returned an attachment upload response without a file ID. The SDK cannot add the file to the outgoing message.
- `controller(.inputAttachmentsNotReady)` — an attachment has no uploaded file ID when preparing a message. All attachments must be uploaded successfully before sending; retry uploading incomplete attachments or remove them.

### File cache errors — `fileCache(FileCacheFailure)`

- `fileCache(.emptyFileID)` — an empty file ID, including whitespace-only strings, was passed when saving a file or updating its data.
- `fileCache(.missingEntry(fileID: String))` — no cache entry with the specified ID was found when updating a file's remote URL. `fileID` contains the missing entry's identifier.
- `fileCache(.operationFailed(String))` — another cache operation failed, such as creating a directory, writing a file, saving the entry index, or removing data. The string describes the underlying error.

### Attachment errors — `attachment(AttachmentFailure)`

- `attachment(.emptyImageData)` — data for the selected image could not be obtained for upload.
- `attachment(.imageTooLarge)` — the image exceeds the `3 × 1024 × 1024` byte limit. Select or prepare a smaller image.
- `attachment(.fileTooLarge)` — the selected document exceeds the `5 × 1024 × 1024` byte limit.
- `attachment(.tooManyAttachments)` — the input field exceeds the limit of 10 attachments. Remove some before adding new ones.
- `attachment(.operationFailed(String))` — another attachment operation failed; the string describes the cause.

### Other errors — `unexpected(String)`

- `unexpected(String)` — an error without a dedicated `ConsultantError` case; the string describes the underlying cause. Encoding and decoding errors in public `Codable` chat link models are also wrapped in this case.
