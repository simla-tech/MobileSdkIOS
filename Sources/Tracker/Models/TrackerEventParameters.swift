import Foundation

/// Identifies an offer using one of the backend's supported identifiers.
public enum TrackerOfferIdentifier: Equatable, Sendable {
    /// Internal CRM offer ID.
    case systemID(Int64)
    /// External offer ID.
    case externalID(String)
    /// Offer XML ID.
    case xmlID(String)
}

/// Optional product details attached to a page view.
public struct TrackerViewedProduct: Equatable, Sendable {
    /// Offer identifier, when the viewed product has an offer.
    public let offer: TrackerOfferIdentifier?
    /// Internal product ID.
    public let productID: Int64?
    /// Offer brand.
    public let brand: String?
    /// External product ID, up to 255 characters.
    public let productExternalID: String?

    /// Creates the product details for `trackPageView`.
    ///
    /// - Parameters:
    ///   - offer: Optional identifier of the viewed offer.
    ///   - productID: Internal retailCRM product ID.
    ///   - brand: Brand of the viewed offer.
    ///   - productExternalID: External retailCRM product ID.
    public init(
        offer: TrackerOfferIdentifier? = nil,
        productID: Int64? = nil,
        brand: String? = nil,
        productExternalID: String? = nil
    ) {
        self.offer = offer
        self.productID = productID
        self.brand = brand
        self.productExternalID = productExternalID
    }
}

/// Backend channel for a customer subscription.
public enum TrackerSubscriptionChannel: String, Equatable, Sendable {
    /// Email subscription.
    case email
    /// SMS subscription.
    case sms
    /// WhatsApp Business API subscription.
    case waba
}

/// Subscription address and its current state.
public struct TrackerSubscription: Equatable, Sendable {
    /// Channel used for the subscription.
    public let channel: TrackerSubscriptionChannel
    /// Email address, phone number, or other channel address.
    public let address: String
    /// Whether the subscription is active.
    public let active: Bool

    /// Creates a subscription value for registration, login, consultation, or subscription events.
    ///
    /// - Parameters:
    ///   - channel: Channel of this customer subscription.
    ///   - address: Subscription address, such as an email or phone number.
    ///   - active: Whether the subscription is active.
    public init(channel: TrackerSubscriptionChannel, address: String, active: Bool) {
        self.channel = channel
        self.address = address
        self.active = active
    }
}

/// Customer attributes included in a registration event.
public struct TrackerCustomer: Equatable, Sendable {
    /// Customer's first name.
    public let firstName: String?
    /// Customer's last name.
    public let lastName: String?
    /// Customer's patronymic.
    public let patronymic: String?
    /// Customer's email address.
    public let email: String?
    /// Customer's phone number.
    public let phone: String?
    /// Subscription states recorded with the registration.
    public let subscriptions: [TrackerSubscription]

    /// Creates the attributes sent with `trackRegister`.
    ///
    /// - Parameters:
    ///   - firstName: Customer first name.
    ///   - lastName: Customer last name.
    ///   - patronymic: Customer patronymic.
    ///   - email: Customer email address.
    ///   - phone: Customer phone number.
    ///   - subscriptions: Subscription states associated with this customer event.
    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        patronymic: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        subscriptions: [TrackerSubscription] = []
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.patronymic = patronymic
        self.email = email
        self.phone = phone
        self.subscriptions = subscriptions
    }
}

/// Supported channel for a contact request.
public enum TrackerContactChannel: String, Equatable, Sendable {
    /// Telegram contact request.
    case telegram
    /// WhatsApp contact request.
    case whatsapp
}

/// One offer and its current quantity in a cart or order.
public struct TrackerCartItem: Equatable, Sendable {
    /// Offer identifier.
    public let offer: TrackerOfferIdentifier
    /// Price per offer.
    public let price: Double
    /// Number of offers.
    public let quantity: Int

    /// Creates an item for cart and order events.
    ///
    /// - Parameters:
    ///   - offer: Identifier of the offer in the cart or order.
    ///   - price: Price per offer.
    ///   - quantity: Quantity of this offer.
    public init(offer: TrackerOfferIdentifier, price: Double, quantity: Int) {
        self.offer = offer
        self.price = price
        self.quantity = quantity
    }
}

/// Identifies an order by internal CRM ID, external ID, or order number.
public enum TrackerOrderIdentifier: Equatable, Sendable {
    /// Internal CRM order ID, from 1 through 2,147,483,647.
    case systemID(Int64)
    /// External order ID.
    case externalID(String)
    /// Order number.
    case number(String)
}
