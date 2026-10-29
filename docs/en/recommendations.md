# Product recommendations

The `recommendations` module retrieves Simla product recommendations and reports recommendation block impressions and product clicks. The application handles product display and navigation.

## Contents

- [Setup](#setup)
- [Customer identification](#customer-identification)
- [Retrieving recommendations](#retrieving-recommendations)
- [Tracking interactions](#tracking-interactions)
- [Public methods and properties](#public-methods-and-properties)
- [Public errors](#public-errors)

## Setup

The module uses the shared `CrmSdk` connection and the shared `Tracker` to send events.
Retrieving products requires an active recommendation mechanic in Simla.
There is no separate `RecommendationsConfig`. See [Tracker setup](./tracker.md#setup).
The shared tracker prepares automatically after the shared session connects.
Assign `onReadyUpdate` to receive the consent form flag and preparation errors.
Setup can run immediately after calling `CrmSdk.initialize`.
Consent is shared with `Tracker`: the application saves the decision and restores it through `setConsent(_:)` before assigning the handler.
If consent was already restored through `Tracker`, it does not need to be restored again.

```swift
import Core
import Recommendations

private func configureConsultant() {
    CrmSdk.initialize(
        config: .init(
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
    configureRecommendations()
}

private func configureRecommendations() {
    let recommendations = CrmSdk.shared.recommendations

    if let savedConsent = UserDefaults.standard.string(forKey: "trackerConsentKey") {
        _ = recommendations.setConsent(savedConsent == "granted" ? .granted : .denied)
    }

    recommendations.onReadyUpdate = { needShowForm, error in
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

## Retrieving recommendations

Retrieving products requires an active recommendation mechanic in Simla. Requirements for customer and product data depend on the mechanic settings.
The SDK automatically uses the customer identity passed through `setCustomerIdentity(_:)`.
If both identifiers are available, `customerId` is used; otherwise, `siteCustomerId` is used. After `setCustomerIdentity(nil)`, customer identifiers are not added to the request.
See [Customer identification](./sdk.md#customer-identification).

```swift
let request = ProductRecommendationsRequest(
    mechanicCode: "mobile-home",
    blockCode: "product_similar",
    productID: 101
)

CrmSdk.shared.recommendations.getProducts(request) { result in
    switch result {
    case .success(let selection):
        // Display selection.products, then call didDisplayRecommendations(selection).
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

The application displays product cards and handles navigation.
`getProducts` works without waiting for tracker preparation or tracking consent: the product request does not check tracker readiness or record an impression.

## Tracking interactions

### Block impression

After displaying the block, call `trackImpression(_:)`:

```swift
private func didDisplayRecommendations(_ selection: ProductRecommendations) {
    CrmSdk.shared.recommendations.trackImpression(
        selection, screenURI: "app://products/101", title: "Product details"
    ) { result in
        if case .failure(let error) = result {
            print(error.localizedDescription)
        }
    }
}
```

### Product click

When a recommended product is selected, call `trackClick(_:)`:

```swift
private func didSelectRecommendation(
    _ product: RecommendedProduct,
    position: Int,
    from selection: ProductRecommendations
) {
    CrmSdk.shared.recommendations.trackClick(
        selection, productID: product.productID, position: position
    ) { result in
        if case .failure(let error) = result {
            print(error.localizedDescription)
        }
    }
}
```

## Public methods and properties

`CrmSdk.shared.recommendations` returns `Recommendations`.

All method variants with `completion` invoke the handler on the main thread.

- `onReadyUpdate: ((Bool, TrackerError?) -> Void)?` — reports automatic shared tracker preparation on the main thread. The flag is `true` only when the site requires consent and the decision is `.unknown`; failures pass `false` and a `TrackerError`. Late subscribers receive the current result. Consent changes update the flag. Reconnection clears the previous result. No callback is delivered before connection unless connection fails. The handler is shared with `Tracker.onReadyUpdate`: assigning it through either module replaces the other module's handler; `nil` clears the shared handler. Readiness does not imply permission to collect events or successful delivery.
- `consentState: TrackerConsentState` — current decision: `.unknown`, `.granted`, or `.denied`.
- `setConsent(_ consent: RecommendationsConsentState) -> Result<Void, RecommendationsError>` — applies the user's decision to the shared tracker; denial clears the event queue.
- `getProducts(_:) async throws -> ProductRecommendations` and `getProducts(_:completion:)` — load a selection using `ProductRecommendationsRequest`. `mechanicCode` is the required nonempty symbolic mechanic code. The code is sent unchanged, and the server validates its format. `blockCode` is a nonempty placement code. An empty selection is a successful result.

  `getProducts` returns `ProductRecommendations`:

  - `executionID` (`UInt64`) — mechanic execution ID used to track impressions and clicks.
  - `personalized` (`Bool`) — whether the selection is personalized.
  - `context` (`ProductRecommendationContext`) — mechanic execution context.
  - `productIds` (`[Int64]`) — IDs of recommended products with available offers.
  - `products` (`[RecommendedProduct]`) — available recommended offers.

  `ProductRecommendationContext` fields:

  - `mechanicType` (`String`) — mechanic type, such as `personal` or `similar`.
  - `required` (`[String]`) — context fields required by the mechanic.

  Fields of each `products` item (`RecommendedProduct`):

  - `id` (`Int64`) — offer ID in Simla.
  - `productID` (`Int64`) — product ID in Simla.
  - `name` (`String`) — offer name, or the product name if the offer name is empty.
  - `price` (`Double`) — current offer price.
  - `oldPrice` (`Double`) — previous price; `0` if absent.
  - `currency` (`String`) — price currency.
  - `imageUrl` (`String`) — offer image URL, or the product image URL if no offer image is available. An empty string if neither is available.
  - `url` (`String`) — product URL; an empty string if absent.
  - `available` (`Bool`) — availability flag returned by the server; `true` if absent.

  If the server omits `productIds`, `products`, or `context.required`, the SDK returns empty arrays for them. An empty selection is a successful result.

- `trackImpression(_:screenURI:title:)` and the `completion` variant — enqueue a recommendation block impression and return the event ID. `screenURI` must be an absolute URI with a scheme.
- `trackClick(_:productID:position:element:leaving:)` and the `completion` variant — enqueue a product card click and return the event ID. `productID` is the product ID from the card; `position` is an optional zero-based index.
- `onEventUpdate: ((TrackerEventUpdate) -> Void)?` — reports event IDs when events are queued, sent, delivered, retried, rejected, or dropped. Uses the shared `Tracker` handler; assigning it through one module replaces the other module's handler. May be called off the main thread.

A successful `trackImpression` or `trackClick` result confirms that the event was queued, not that it was delivered to the server.
`trackImpression` and `trackClick` use the shared `Tracker` startup buffer and queue.
There is no need to wait for startup to complete before calling them.

## Public errors

Public errors conform to `LocalizedError`.
Messages for predefined states are available in Russian, English, and Spanish.
Diagnostic details and server messages may remain in their original language.

The public error type of `Recommendations` is `RecommendationsError`.

`Recommendations` operations return this error type through `throw` or `completion`.
The shared `onReadyUpdate` handler receives `TrackerError`; see [Tracker public errors](./tracker.md#public-errors).

- `invalidRequest(String)` — invalid request or event parameters.
- `missingConnection` — no connected session credentials.
- `httpStatus(Int, [String])` — HTTP status and backend messages from `errors`.
- `invalidResponse(String)`, `requestFailed(String)` — response or request failure.
- `trackingUnavailable`, `consentRequired`, `trackingFailed(String)` — the tracker did not accept the event.
- `cancelled` — the operation was cancelled.
