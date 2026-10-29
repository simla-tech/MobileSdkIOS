import Foundation

package struct PushMessage {
    package let pushId: String
    package let title: String?
    package let body: String?
    package let imageURL: URL?
    package let clickAction: ClickAction?
    package let rgCategory: String?
    package let buttons: [PushButton]
    private let userInfo: [AnyHashable: Any]

    package init(
        pushId: String,
        title: String?,
        body: String?,
        imageURL: URL?,
        clickAction: ClickAction?,
        rgCategory: String?,
        buttons: [PushButton],
        userInfo: [AnyHashable: Any]
    ) {
        self.pushId = pushId
        self.title = title
        self.body = body
        self.imageURL = imageURL
        self.clickAction = clickAction
        self.rgCategory = rgCategory
        self.buttons = buttons
        self.userInfo = userInfo
    }
}

package struct ClickAction: Equatable {
    package let stringUrl: String
    package let customAttributes: [String: String]?

    package init(stringUrl: String, customAttributes: [String: String]?) {
        self.stringUrl = stringUrl
        self.customAttributes = customAttributes
    }
}

package struct PushButton: Equatable {
    package let title: String
    package let value: String

    package init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}
