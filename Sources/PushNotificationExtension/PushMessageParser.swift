import Foundation

package enum PushMessageParser {
    private static let crmPushIDUserInfoKey = "r_group_push"
    private static let pushIDUserInfoKey = "push_id"
    private static let customAttributePrefix = "ca_"

    package static func parseSilent(userInfo: [AnyHashable: Any]) -> PushMessage? {
        guard
            let aps = userInfo["aps"] as? [String: Any],
            let contentAvailable = aps["content-available"] as? NSNumber,
            contentAvailable.intValue == 1,
            aps["alert"] == nil,
            aps["sound"] == nil,
            aps["badge"] == nil
        else {
            return nil
        }
        return PushMessageParser.parse(userInfo: userInfo)
    }

    package static func parse(
        userInfo: [AnyHashable: Any],
        title notificationTitle: String? = nil,
        body notificationBody: String? = nil
    ) -> PushMessage? {
        guard isValidFingerprint(userInfo: userInfo) else {
            return nil
        }

        guard
            let pushId = stringValue(from: userInfo[pushIDUserInfoKey]),
            isValidPushId(pushId)
        else {
            return nil
        }

        return PushMessage(
            pushId: pushId,
            title: notificationTitle ?? stringValue(for: ["gcm.n.title", "gcm.notification.title", "title"], in: userInfo),
            body: notificationBody ?? stringValue(for: ["gcm.n.body", "gcm.notification.body", "body"], in: userInfo),
            imageURL: urlValue(for: ["image_url", "image", "gcm.n.image", "gcm.notification.image"], in: userInfo),
            clickAction: {
                let stringUrl = stringValue(for: ["click_action", "url", "link"], in: userInfo)
                let attributes = customAttributes(from: userInfo)
                if let stringUrl {
                    return ClickAction(stringUrl: stringUrl, customAttributes: attributes.isEmpty ? nil : attributes)
                }
                return nil
            }(),
            rgCategory: stringValue(for: ["r_group_category"], in: userInfo),
            buttons: buttons(from: userInfo["buttons"]),
            userInfo: userInfo
        )
    }
}

private extension PushMessageParser {

    static func isValidFingerprint(userInfo: [AnyHashable: Any]) -> Bool {
        let value = userInfo[crmPushIDUserInfoKey]

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? Int {
            return number == 1
        }

        if let number = value as? NSNumber {
            return number.intValue == 1
        }

        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true"
        }

        return false
    }

    static func isValidPushId(_ pushId: String) -> Bool {
        guard
            let pushId = pushId.nilIfEmpty,
            let separatorIndex = pushId.firstIndex(of: "_"),
            separatorIndex != pushId.startIndex,
            separatorIndex != pushId.index(before: pushId.endIndex)
        else {
            return false
        }

        let appPart = pushId[..<separatorIndex]
        let idPart = pushId[pushId.index(after: separatorIndex)...]

        return !appPart.contains { $0 == "_" || $0.isWhitespace }
            && !idPart.contains { $0.isWhitespace }
    }

    static func buttons(from value: Any?) -> [PushButton] {
        guard
            let string = stringValue(from: value),
            let data = string.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            let dictionaries = json as? [[AnyHashable: Any]]
        else {
            return []
        }

        return dictionaries.compactMap { dictionary in
            guard
                let title = stringValue(from: dictionary["title"]),
                let value = stringValue(from: dictionary["value"])
            else {
                return nil
            }

            return PushButton(title: title, value: value)
        }
    }

    static func customAttributes(from userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [String: String]()) { result, element in
            guard
                let key = element.key.base as? String,
                key.hasPrefix(customAttributePrefix)
            else {
                return
            }

            let attributeKey = String(key.dropFirst(customAttributePrefix.count))
            guard
                !attributeKey.isEmpty,
                let value = customAttributeValue(from: element.value)
            else {
                return
            }

            result[attributeKey] = value
        }
    }

    static func customAttributeValue(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    static func stringValue(
        for keys: [String],
        in dictionary: [AnyHashable: Any]
    ) -> String? {
        keys
            .lazy
            .compactMap { stringValue(from: dictionary[$0]) }
            .first
    }

    static func urlValue(
        for keys: [String],
        in dictionary: [AnyHashable: Any]
    ) -> URL? {
        keys
            .lazy
            .compactMap { stringValue(from: dictionary[$0]) }
            .compactMap(validURL(from:))
            .first
    }

    static func stringValue(from value: Any?) -> String? {
        if let string = value as? String {
            return string.nilIfEmpty
        }

        if let number = value as? NSNumber {
            return number.stringValue.nilIfEmpty
        }

        return nil
    }

    static func validURL(from string: String) -> URL? {
        guard
            let url = URL(string: string),
            url.scheme?.nilIfEmpty != nil
        else {
            return nil
        }

        return url
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
