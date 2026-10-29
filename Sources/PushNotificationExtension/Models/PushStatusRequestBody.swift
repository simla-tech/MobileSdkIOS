import Foundation

package struct PushStatusRequestBody: Codable, Equatable, Sendable {
    package let changedAt: Int64
    package let pushId: String
    package let status: PushNotificationStatus
    package let buttonHash: String?

    private enum CodingKeys: String, CodingKey {
        case changedAt = "changed_at"
        case pushId = "push_id"
        case status
        case buttonHash = "button_hash"
    }

    package init(
        changedAt: Int64,
        pushId: String,
        status: PushNotificationStatus,
        buttonHash: String?
    ) {
        self.changedAt = changedAt
        self.pushId = pushId
        self.status = status
        self.buttonHash = buttonHash
    }
}
