# Tracker

The `tracker` module sends application events to Simla: screen and product views,
clicks, customer registration and sign-in, cart changes, and orders.

## Contents

- [Setup](#setup)
- [Customer identification](#customer-identification)
- [Public methods and properties](#public-methods-and-properties)
- [Custom events](#custom-events)
- [Queue and delivery](#queue-and-delivery)
- [Diagnostics](#diagnostics)
- [Public errors](#public-errors)

## Setup

Pass the settings when initializing the SDK. The tracker is created on first access to
`CrmSdk.shared.tracker` and automatically prepares its local queue after the shared session connects.
Call `configureTracker()` immediately after `CrmSdk.initialize(...)`.
Assign `onReadyUpdate` to receive whether the consent form is needed and any preparation error.
The handler runs on the main thread; late subscribers receive the current result.
If a form is needed, show it and pass the decision through `setConsent(_:)`.
The SDK does not persist consent across launches. Restore the saved decision through `setConsent(_:)`
before assigning the handler to avoid showing the form again.

```swift

import Core
import Tracker

CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>",
        trackerConfig: TrackerConfig(
            batchSize: 50,
            flushInterval: 15,
            timeSyncInterval: 60 * 60
        )
    )
) { result in
    if case .failure(let error) = result {
        print(error.localizedDescription)
    }
}
configureTracker()

private func configureTracker() {
    let tracker = CrmSdk.shared.tracker
    if let savedConsent = UserDefaults.standard.string(forKey: "trackerConsentKey") {
        tracker.setConsent(savedConsent == "granted" ? .granted : .denied)
    }
    tracker.onReadyUpdate = { needShowForm, error in
        if let error {
            print(error.localizedDescription)
        } else if needShowForm {
            // Show the consent form and pass the decision through setConsent(_:).
        }
    }
}
```

### Configuring `TrackerConfig`

Pass `TrackerConfig` to `CrmSdkConfig(trackerConfig:)` to override the defaults:

- `batchSize` — maximum number of events per batch, from 1 to 50; default: 50.
- `flushInterval` — sending interval in seconds, from 0 to 86,400; default: 15. A value of 0 disables periodic sending.
- `timeSyncInterval` — server time synchronization interval in seconds, from 0 to 86,400; default: 3600.

## Customer identification

Notify the SDK of sign-in, account changes, and sign-out through `CrmSdk.shared.setCustomerIdentity(...)`.
See [Customer identification](./sdk.md#customer-identification).

## Public methods and properties

`CrmSdk.shared.tracker` returns `Tracker`.

- `onReadyUpdate: ((Bool, TrackerError?) -> Void)?` — reports automatic preparation on the main thread. The flag is `true` only when consent is required and the decision is `.unknown`; errors are passed with `false`. Assignment replays the current result if preparation has completed. Consent changes refresh the flag; reconnection clears the previous result until preparation completes again. No callback is emitted while awaiting a connection unless the connection fails. Shared connection and local queue errors use `TrackerError`. Readiness does not imply consent or server delivery, and tracking may be disabled by the site. Assign `nil` to unsubscribe.
- `consentState: TrackerConsentState` — current decision: `.unknown`, `.granted`, or `.denied`.
- `onEventUpdate: ((TrackerEventUpdate) -> Void)?` — reports event IDs when events are queued, sent, delivered, retried, rejected, or dropped. May be called off the main thread.
- `setConsent(_:) -> Result<Void, TrackerError>` — applies the user's decision and clears the queue on denial.
- `flushAll() async throws` and `flushAll(completion:)` — attempt to send all events from the current queue. Partial delivery returns `.flushIncomplete([String])` with the IDs of events not delivered.

All `track*` methods have `async throws -> String` and `completion` variants. The `completion` variant returns immediately and invokes its handler on the main thread with `Result<String, TrackerError>`. Success contains the ID of the event accepted into the startup buffer or saved to the queue, not confirmation of server delivery. Removal of accepted events is reported through `onEventUpdate.dropped`.

- `trackPageView(screenURI:title:product:code:completion:)` — `page_view`; sets the current page and the previous page URL for subsequent events. `screenURI` must be an absolute URI. `TrackerViewedProduct` accepts an offer ID, an internal or external product ID, and a brand.
- `trackClick(element:leaving:code:completion:)` — `click`; an element click.
- `trackRegister(customer:createCustomer:createCustomerByEmail:code:completion:)` — `register`; customer and subscription data. `createCustomer` defaults to `false`. Set it to `true` to request customer creation in the CRM; creation by email also requires `createCustomerByEmail: true` and the customer's email. Successfully queuing a registration event does not confirm that a CRM customer was created.
- `trackLogin(customerEmail:subscriptions:code:completion:)` — `login`; customer sign-in.
- `trackConsult(customerEmail:subscriptions:code:completion:)` — `consult`; an attempt to contact a consultant.
- `trackOpenCart(customerEmail:code:completion:)` — `open_cart`; opening the cart.
- `trackContact(channel:code:completion:)` — `contact`; a request to connect through Telegram or WhatsApp.
- `trackCart(cartID:items:code:completion:)` — `cart`; a change to cart contents.
- `trackOrder(identifier:cartID:items:deliveryPrice:total:code:completion:)` — `order`; placing an order. `identifier`: `.systemID(Int64)` — internal CRM order ID (`order_id`), `.externalID(String)` — external ID (`order_external_id`), `.number(String)` — order number (`order_number`).
- `trackSubscription(_:code:completion:)` — `subscription`; a subscription change.
- `trackFormStart(formSelector:code:completion:)` — `form_start`; starting to fill out a form.
- `trackFormSubmit(formSelector:code:completion:)` — `form_submit`; submitting a form.
- `trackFileDownload(fileName:element:code:completion:)` — `file_download`; downloading a file.
- `trackFavoriteProduct(offer:removed:code:completion:)` — `favorite_product`; adding an offer to favorites or removing it.

When a push notification or its button is tapped, the SDK stores its UTM tags and automatically adds them to subsequent `order` events. A new push with tags replaces the set; a push without tags does not clear it. The active set remains until the application process terminates. Created events retain their own tags in SQLite and send them on retry, including after an application restart. The push field `utm_term` is sent as `utm_keyword` inside `utm`.

## Custom events

All `track*()` methods accept an optional `code` parameter. Use the value from the event settings in the Simla administration panel.

## Queue and delivery

A successful `track*` call confirms acceptance into the startup buffer or SQLite queue, not server delivery.
Delivery results are available through `onEventUpdate`.

### Startup buffer

Before the tracker is ready, events can be stored in memory when consent is `.unknown` or `.granted`.
The buffer holds up to 1000 events; the oldest are dropped when capacity is exceeded.
It preserves event IDs, timestamps, order, and context.

After SQLite is prepared, events are transferred to the persistent queue if the server allows tracking and consent requirements are met. If tracking is disabled or required consent has not been granted, the buffer is cleared. Consent denial, session disconnection, and customer changes also clear it.
Events are lost on application termination until transferred to SQLite.

### Persistent queue

SQLite stores a single queue of up to 1000 events owned by `siteToken` + `userToken`.
The oldest events are dropped when capacity is exceeded; merging a restored queue with the startup buffer also retains only the latest 1000 events.
On restart with the same owner, the queue is restored if tracking settings and consent permit its use.
Changing the owner removes previous data.
Changing `customerIdentity`, including sign-out, removes regular and oversized events before reconnecting.
When opening a database from an earlier SDK version, only the current owner's data is retained, subject to the same limits.

### Sending and retries

The SDK automatically attempts to send one batch after preparing the queue on connection, when `batchSize` events accumulate, and at the `flushInterval` interval.
Setting `flushInterval = 0` disables periodic sending.

Batches contain whole events and respect `batchSize` and JSON size: the target size is 1 KiB below the 1 MiB limit (`1,048,576` bytes). An event is never split.
If a request containing a single event exceeds the limit, the SDK rejects it before sending with `eventTooLarge`.
On HTTP 413 for a batch, the SDK retries events individually.
HTTP 413 for a single event also causes rejection.
These events are excluded from the regular queue and are not retried: the latest 50 are stored separately, with the oldest removed as new ones are added.

Delivered events and events permanently rejected by the server are removed from the queue.
Events with temporary errors remain for subsequent delivery attempts.
On HTTP 429, the SDK respects `Retry-After`; manual sending does not bypass this restriction.

### Manual sending

`flushAll()` attempts to send all events present in the persistent queue at the time of the call, using multiple batches. New events and the startup buffer are excluded from this attempt.
The method respects connection readiness, consent, and server restrictions.
If some events are not delivered, it returns `flushIncomplete([String])` with their IDs, including the IDs of stored oversized events.
If there is no connection or consent, or requests are rate limited, the method may return the corresponding error.

```swift
do {
    try await CrmSdk.shared.tracker.flushAll()
} catch {
    print(error.localizedDescription)
}
```

After reconnecting, the SDK automatically resumes queue processing.
To attempt delivery of accumulated events before changing the customer or signing out, call `flushAll()` and wait for its result before `setCustomerIdentity(_:)`: remaining events are removed when the customer changes.

## Diagnostics

Use `onEventUpdate` to observe event delivery:

```swift
import Core
import Tracker

Task { @MainActor in
    CrmSdk.shared.tracker.onEventUpdate = { event in
        switch event {
        case .queued(let ids):
            // Events added to the queue     
            print("CrmSdk.shared.tracker.onEventUpdate queued = \(ids)")
        case .sending(let ids, let payload):
            // Starting a batch delivery attempt
            print("CrmSdk.shared.tracker.onEventUpdate sending = \(ids), payload = \(payload)")
        case .delivered(let ids):
            // The server accepted the events  
            print("CrmSdk.shared.tracker.onEventUpdate delivered = \(ids)")
        case .retryScheduled(let ids, let error):
            // Events retained for retry
            print("CrmSdk.shared.tracker.onEventUpdate retryScheduled = \(ids), error = \(error)")
        case .rejected(let id, let error):
            // Event permanently rejected by the server       
            print("CrmSdk.shared.tracker.onEventUpdate rejected = \(id), error = \(error)")
        case .dropped(let ids, let reason):
            // Events removed when clearing the queue or exceeding its capacity  
            print("CrmSdk.shared.tracker.onEventUpdate dropped = \(ids), reason = \(reason)")
        }
    }
}
```

## Public errors

Public errors conform to `LocalizedError`.
Messages for predefined states are available in Russian, English, and Spanish.
Diagnostic details and server messages may remain in their original language.

The public error type of `Tracker` is `TrackerError`.

Preparation errors are reported through `onReadyUpdate`. Methods `track*` and `flushAll` pass `TrackerError` through `throw` or `completion`; `setConsent(_:)` returns it in `Result`. `onEventUpdate` uses the same type for event errors.
Error descriptions and reasons generated by the SDK are localized into Russian, English, and Spanish. System error details and server responses remain in their original language.

- `invalidEvent(String)` — invalid event parameters.
- `eventTooLarge(sizeBytes:limitBytes:)` — the SDK rejected the event before sending: the JSON request size exceeds the local limit.
- `unavailable`, `consentRequired`, `missingConnection` — sending is unavailable, consent is required, or there is no connection.
- `storage(String)` — local queue failure.
- `requestEncodingFailed(String)`, `requestFailed(String)`, `invalidResponse(String)` — request or response failure.
- `httpStatus(Int, [String], retryAfter: TimeInterval?)` — HTTP status, server messages, and retry interval.
- `eventRejected(String)` — the server rejected an individual event.
- `flushIncomplete([String])` — some events were not sent after `flushAll`; the array contains their IDs.
