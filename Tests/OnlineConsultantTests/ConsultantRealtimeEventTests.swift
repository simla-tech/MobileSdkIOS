import XCTest
@testable import OnlineConsultant

final class ConsultantRealtimeEventTests: XCTestCase {

    func testDecodesMessageEvent() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "message",
              "data": {
                "id": "24077908",
                "content": "Здравствуйте",
                "time": "2026-06-24T11:30:35.090792Z",
                "updated_at": "2026-06-24T11:30:35.09123Z",
                "from_me": false,
                "type": "text",
                "status": "sent",
                "quote_content": "Цитата",
                "user": {
                  "first_name": "Юрий",
                  "last_name": "Девятаев",
                  "avatar": "https://example.com/avatar.png"
                }
              }
            }
            """
        )

        guard case .message(let message) = event else {
            return XCTFail("Expected message event")
        }

        XCTAssertEqual(message.id?.value, "24077908")
        XCTAssertEqual(message.content, "Здравствуйте")
        XCTAssertEqual(message.time, "2026-06-24T11:30:35.090792Z")
        XCTAssertEqual(message.updatedAt, "2026-06-24T11:30:35.09123Z")
        XCTAssertEqual(message.fromMe, false)
        XCTAssertEqual(message.messageType, "text")
        XCTAssertEqual(message.status, "sent")
        XCTAssertEqual(message.quoteContent, "Цитата")
        XCTAssertEqual(message.user?.firstName, "Юрий")
        XCTAssertEqual(message.user?.lastName, "Девятаев")
        XCTAssertEqual(message.user?.avatar, "https://example.com/avatar.png")
    }

    func testDecodesFlexibleNumericMessageID() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "message",
              "data": {
                "id": 24077908,
                "content": "Здравствуйте"
              }
            }
            """
        )

        guard case .message(let message) = event else {
            return XCTFail("Expected message event")
        }

        XCTAssertEqual(message.id?.value, "24077908")
    }

    func testDecodesProductMessageEvent() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "message",
              "data": {
                "id": "103",
                "type": "product",
                "content": "",
                "product": {
                  "name": "Chocolate candies",
                  "img": "https://example.test/products/77.png",
                  "unit": "pcs",
                  "cost": {
                    "value": 12.9,
                    "currency": "USD"
                  },
                  "quantity": {
                    "value": 7,
                    "unit": "pcs"
                  }
                }
              }
            }
            """
        )

        guard case .message(let message) = event else {
            return XCTFail("Expected message event")
        }

        XCTAssertEqual(message.id?.value, "103")
        XCTAssertEqual(message.messageType, "product")
        XCTAssertEqual(message.product?.name, "Chocolate candies")
        XCTAssertEqual(message.product?.img, "https://example.test/products/77.png")
        XCTAssertEqual(message.product?.unit, "pcs")
        XCTAssertEqual(message.product?.cost?.value, 12.9)
        XCTAssertEqual(message.product?.cost?.currency, "USD")
        XCTAssertEqual(message.product?.quantity?.value, 7)
        XCTAssertEqual(message.product?.quantity?.unit, "pcs")
    }

    func testDecodesOrderMessageEvent() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "message",
              "data": {
                "id": "104",
                "type": "order",
                "content": "",
                "order": {
                  "external_id": 501,
                  "number": "10042",
                  "url": "https://example.test/orders/10042",
                  "cost": {
                    "value": 3700,
                    "currency": "RUB"
                  },
                  "items": [
                    {
                      "external_id": 1001,
                      "name": "Увлажняющий крем",
                      "url": "https://example.test/products/cream",
                      "price": {
                        "value": 1200,
                        "currency": "RUB"
                      },
                      "quantity": {
                        "value": 2,
                        "unit": "шт"
                      }
                    }
                  ],
                  "delivery": {
                    "name": "Курьер",
                    "address": "Москва, Тверская улица, 7",
                    "comment": "Позвонить за час",
                    "price": {
                      "value": 300,
                      "currency": "RUB"
                    }
                  },
                  "discount": {
                    "value": 250,
                    "currency": "RUB"
                  },
                  "payments": [
                    {
                      "name": "Картой",
                      "amount": {
                        "value": 3450,
                        "currency": "RUB"
                      },
                      "status": {
                        "name": "Оплачено",
                        "payed": true
                      }
                    }
                  ],
                  "status": {
                    "code": "new",
                    "name": "Новый"
                  },
                  "date": "2026-06-30T09:40:00Z"
                }
              }
            }
            """
        )

        guard case .message(let message) = event else {
            return XCTFail("Expected message event")
        }

        XCTAssertEqual(message.id?.value, "104")
        XCTAssertEqual(message.messageType, "order")
        XCTAssertEqual(message.order?.number?.value, "10042")
        XCTAssertEqual(message.order?.items.first?.name, "Увлажняющий крем")
        XCTAssertEqual(message.order?.items.first?.url, "https://example.test/products/cream")
        XCTAssertEqual(message.order?.items.first?.quantity?.value, 2)
        XCTAssertEqual(message.order?.payments.first?.amount?.value, 3450)
        XCTAssertEqual(message.order?.payments.first?.amount?.currency, "RUB")
        XCTAssertEqual(message.order?.payments.first?.name, "Картой")
        XCTAssertEqual(message.order?.payments.first?.status?.name, "Оплачено")
        XCTAssertEqual(message.order?.payments.first?.status?.payed, true)
        XCTAssertEqual(
            message.orderNumberLabel,
            ConsultantLocalization.orderLabelNumber.format("10042")
        )
        XCTAssertEqual(message.orderDisplayItems.first?.name, "Увлажняющий крем")
        XCTAssertTrue(message.orderDisplayItems.first?.details.contains("2 шт") == true)
        XCTAssertTrue(message.orderDisplayItems.first?.details.contains("1") == true)
        XCTAssertEqual(
            message.orderDisplayFields.map(\.title),
            [
                ConsultantLocalization.orderFieldDelivery.localized,
                ConsultantLocalization.orderFieldAddress.localized,
                ConsultantLocalization.orderFieldComment.localized,
                ConsultantLocalization.orderFieldDeliveryCost.localized,
                ConsultantLocalization.orderFieldDiscount.localized,
                ConsultantLocalization.orderFieldTotal.localized,
                ConsultantLocalization.orderFieldPayment.localized
            ]
        )
    }

    func testDecodesOfflineStatusEvent() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "offline_status",
              "data": {
                "is_offline": true
              }
            }
            """
        )

        XCTAssertEqual(event, .offlineStatus(ConsultantOfflineStatus(isOffline: true)))
    }

    func testDecodesUnknownEventWithoutFailure() throws {
        let event = try ConsultantRealtimeEvent(
            rawText: """
            {
              "type": "custom_event",
              "data": {
                "enabled": true
              }
            }
            """
        )

        XCTAssertEqual(
            event,
            .unknown(type: "custom_event", data: .object(["enabled": .bool(true)]))
        )
    }
}
