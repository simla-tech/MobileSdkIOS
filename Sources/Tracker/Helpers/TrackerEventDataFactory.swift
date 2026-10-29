import Foundation

package enum TrackerEventDataFactory {
    package typealias Data = [String: TrackerEventDataValue]

    package static func pageView(_ product: TrackerViewedProduct?) throws -> Data? {
        guard let product else { return nil }
        var data: Data = [:]
        try addOffer(product.offer, to: &data)
        if let productExternalID = product.productExternalID {
            let value = try required(productExternalID, "product_external_id")
            guard value.unicodeScalars.count <= 255 else {
                throw TrackerError.invalidEvent(TrackerLocalization.identifierTooLong.format("product_external_id", 255))
            }
            data["product_external_id"] = .string(value)
        }
        if let productID = product.productID {
            guard productID > 0, productID <= Int64(UInt32.max) else {
                throw TrackerError.invalidEvent(TrackerLocalization.positiveUInt32.format("productID"))
            }
            data["product_id"] = .int(Int(productID))
        }
        if let brand = product.brand?.nilIfEmpty { data["offer_brand"] = .string(brand) }
        guard !data.isEmpty else {
            throw TrackerError.invalidEvent(TrackerLocalization.productIdentityRequired.localized)
        }
        return data
    }

    package static func click(element: String, leaving: Bool) throws -> Data {
        ["el": .string(try required(element, "element")), "leaving": .bool(leaving)]
    }

    package static func register(customer: TrackerCustomer) throws -> Data {
        var data: Data = [:]
        if let value = customer.firstName?.nilIfEmpty { data["customer_first_name"] = .string(value) }
        if let value = customer.lastName?.nilIfEmpty { data["customer_last_name"] = .string(value) }
        if let value = customer.patronymic?.nilIfEmpty { data["customer_patronymic"] = .string(value) }
        if let value = customer.email?.nilIfEmpty { data["customer_email"] = .string(value) }
        if let value = customer.phone?.nilIfEmpty { data["customer_phone"] = .string(value) }
        if !customer.subscriptions.isEmpty {
            data["subscriptions"] = .array(try customer.subscriptions.map(subscriptionValue))
        }
        guard !data.isEmpty else {
            throw TrackerError.invalidEvent(TrackerLocalization.customerAttributeRequired.localized)
        }
        return data
    }

    package static func customerEmail(_ email: String, subscriptions: [TrackerSubscription]) throws -> Data {
        var data: Data = ["customer_email": .string(try required(email, "customerEmail"))]
        if !subscriptions.isEmpty {
            data["subscriptions"] = .array(try subscriptions.map(subscriptionValue))
        }
        return data
    }

    package static func openCart(customerEmail: String?) throws -> Data? {
        guard let customerEmail else { return nil }
        return ["customer_email": .string(try required(customerEmail, "customerEmail"))]
    }

    package static func contact(_ channel: TrackerContactChannel) -> Data {
        ["contact_channel": .string(channel.rawValue)]
    }

    package static func cart(id: String, items: [TrackerCartItem]) throws -> Data {
        var data: Data = ["cart_id": .string(try required(id, "cartID"))]
        if !items.isEmpty { data["items"] = .array(try items.map(itemValue)) }
        return data
    }

    package static func order(
        identifier: TrackerOrderIdentifier,
        cartID: String?,
        items: [TrackerCartItem],
        deliveryPrice: Double?,
        total: Double?
    ) throws -> Data {
        var data: Data = [:]
        switch identifier {
        case let .systemID(value):
            guard value > 0, value <= Int64(Int32.max) else {
                throw TrackerError.invalidEvent(TrackerLocalization.orderSystemIDOutOfRange.localized)
            }
            data["order_id"] = .int(Int(value))
        case let .externalID(value): data["order_external_id"] = .string(try required(value, "orderExternalID"))
        case let .number(value): data["order_number"] = .string(try required(value, "orderNumber"))
        }
        if let cartID { data["cart_id"] = .string(try required(cartID, "cartID")) }
        if !items.isEmpty { data["items"] = .array(try items.map(itemValue)) }
        if let deliveryPrice {
            data["delivery_price"] = .double(try nonNegative(deliveryPrice, "deliveryPrice"))
        }
        if let total { data["total"] = .double(try nonNegative(total, "total")) }
        return data
    }

    package static func subscription(_ subscription: TrackerSubscription) throws -> Data {
        guard case let .object(data) = try subscriptionValue(subscription) else { return [:] }
        return data
    }

    package static func form(_ selector: String) throws -> Data {
        ["form_selector": .string(try required(selector, "formSelector"))]
    }

    package static func fileDownload(fileName: String, element: String?) throws -> Data {
        var data: Data = ["file_name": .string(try required(fileName, "fileName"))]
        if let element { data["el"] = .string(try required(element, "element")) }
        return data
    }

    package static func favoriteProduct(offer: TrackerOfferIdentifier, removed: Bool) throws -> Data {
        var data: Data = ["removed": .bool(removed)]
        try addOffer(offer, to: &data)
        return data
    }

    package static func code(_ value: String?) throws -> String? {
        guard let value else { return nil }
        return try required(value, "code")
    }

    package static func absoluteURI(_ value: String, name: String) throws -> String {
        let value = try required(value, name)
        guard let url = URL(string: value), url.scheme != nil else {
            throw TrackerError.invalidEvent(TrackerLocalization.absoluteURIRequired.format(name))
        }
        return url.absoluteString
    }

    private static func itemValue(_ item: TrackerCartItem) throws -> TrackerEventDataValue {
        guard item.quantity > 0, item.quantity <= Int(UInt32.max) else {
            throw TrackerError.invalidEvent(TrackerLocalization.positiveUInt32.format("quantity"))
        }
        var data: Data = [
            "price": .double(try nonNegative(item.price, "price")),
            "quantity": .int(item.quantity)
        ]
        try addOffer(item.offer, to: &data, item: true)
        return .object(data)
    }

    private static func subscriptionValue(_ subscription: TrackerSubscription) throws -> TrackerEventDataValue {
        .object([
            "channel": .string(subscription.channel.rawValue),
            "subscription": .string(try required(subscription.address, "subscription address")),
            "active": .bool(subscription.active)
        ])
    }

    private static func addOffer(_ offer: TrackerOfferIdentifier?, to data: inout Data, item: Bool = false) throws {
        guard let offer else { return }
        switch offer {
        case let .systemID(id):
            guard id > 0, id <= (item ? Int64.max : Int64(UInt32.max)) else {
                throw TrackerError.invalidEvent(TrackerLocalization.offerSystemIDOutOfRange.localized)
            }
            data[item ? "id" : "offer_id"] = .int(Int(id))
        case let .externalID(id):
            let id = try required(id, "offer_external_id")
            guard id.unicodeScalars.count <= 255 else {
                throw TrackerError.invalidEvent(TrackerLocalization.identifierTooLong.format("offer_external_id", 255))
            }
            data[item ? "external_id" : "offer_external_id"] = .string(id)
        case let .xmlID(id):
            let id = try required(id, "offer_xml_id")
            guard id.unicodeScalars.count <= 255 else {
                throw TrackerError.invalidEvent(TrackerLocalization.identifierTooLong.format("offer_xml_id", 255))
            }
            data[item ? "xml_id" : "offer_xml_id"] = .string(id)
        }
    }

    private static func required(_ value: String, _ name: String) throws -> String {
        guard let value = value.nilIfEmpty else {
            throw TrackerError.invalidEvent(TrackerLocalization.fieldRequired.format(name))
        }
        return value
    }

    private static func nonNegative(_ value: Double, _ name: String) throws -> Double {
        guard value.isFinite, value >= 0 else {
            throw TrackerError.invalidEvent(TrackerLocalization.nonNegativeNumber.format(name))
        }
        return value
    }
}
