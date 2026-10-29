import Foundation

/// Order payload attached to an order message.
package struct MessageOrder: Codable, Equatable, Sendable {

    /// Customer-visible order number from backend `order.number`.
    package let number: FlexibleID?

    /// Primary order total payload from backend `order.cost`.
    package let cost: MessageProductCost?

    /// Order item list from backend `order.items`.
    package let items: [MessageOrderItem]

    /// Delivery payload from backend `order.delivery`.
    package let delivery: MessageOrderDelivery?

    /// Discount payload from backend `order.discount`.
    package let discount: MessageProductCost?

    /// Payment list from backend `order.payments`.
    package let payments: [MessageOrderPayment]

    /// Creates an order payload for an order message.
    package init(
        number: FlexibleID? = nil,
        cost: MessageProductCost? = nil,
        items: [MessageOrderItem] = [],
        delivery: MessageOrderDelivery? = nil,
        discount: MessageProductCost? = nil,
        payments: [MessageOrderPayment] = []
    ) {
        self.number = number
        self.cost = cost
        self.items = items
        self.delivery = delivery
        self.discount = discount
        self.payments = payments
    }

    /// Decodes an order payload, defaulting missing item and payment arrays to empty arrays.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.number = try container.decodeIfPresent(FlexibleID.self, forKey: .number)
        self.cost = try container.decodeIfPresent(MessageProductCost.self, forKey: .cost)
        self.items = try container.decodeIfPresent([MessageOrderItem].self, forKey: .items) ?? []
        self.delivery = try container.decodeIfPresent(MessageOrderDelivery.self, forKey: .delivery)
        self.discount = try container.decodeIfPresent(MessageProductCost.self, forKey: .discount)
        self.payments = try container.decodeIfPresent([MessageOrderPayment].self, forKey: .payments) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case cost
        case items
        case delivery
        case discount
        case payments
    }
}

package extension MessageOrder {

    /// Formatted order number label for UI display.
    var formattedOrderNumberLabel: String? {
        guard let number = number?.value.nilIfEmpty else {
            return nil
        }

        return ConsultantLocalization.orderLabelNumber.format(number)
    }

    /// Order items prepared for UI display.
    var displayItems: [MessageOrderDisplayItem] {
        items.enumerated().compactMap { index, item in
            guard let name = item.name?.nilIfEmpty else {
                return nil
            }

            return .init(
                numberLabel: "\(index + 1).",
                name: name,
                details: item.formattedDetails,
                url: item.url.flatMap(URL.init(string:))
            )
        }
    }

    /// Order summary fields prepared for UI display.
    var displayFields: [MessageOrderDisplayField] {
        var fields: [MessageOrderDisplayField] = []

        if let deliveryName = delivery?.name?.nilIfEmpty {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldDelivery.localized,
                value: deliveryName
            ))
        }

        if let address = delivery?.address?.nilIfEmpty {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldAddress.localized,
                value: address
            ))
        }

        if let deliveryComment = delivery?.comment?.nilIfEmpty {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldComment.localized,
                value: deliveryComment
            ))
        }

        if let deliveryPrice = delivery?.price?.formattedMoneyLabel {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldDeliveryCost.localized,
                value: deliveryPrice
            ))
        }

        if let discount = discount?.formattedMoneyLabel {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldDiscount.localized,
                value: discount
            ))
        }

        if let total = cost?.formattedMoneyLabel {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldTotal.localized,
                value: total
            ))
        }

        if let payment = formattedPaymentLabel {
            fields.append(.init(
                title: ConsultantLocalization.orderFieldPayment.localized,
                value: payment
            ))
        }

        return fields
    }

    /// Formatted payment label built from backend `order.payments`.
    private var formattedPaymentLabel: String? {
        let paymentLabels = payments.compactMap(\.formattedLabel)
        return paymentLabels.isEmpty ? nil : paymentLabels.joined(separator: "\n")
    }
}
