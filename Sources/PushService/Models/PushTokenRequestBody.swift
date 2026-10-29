import Foundation

package struct PushTokenRequestBody: Encodable, Equatable, Sendable {
    package let customerId: Int64?
    package let customerExternalId: String?
    package let crmSiteCode: String?
    package let token: String?
    package let fid: String?
    package let type: String
    package let deviceType: String
    package let categories: [String]

    package init(
        customerId: Int64?,
        customerExternalId: String?,
        crmSiteCode: String?,
        token: String?,
        fid: String?,
        firebaseProjectId: String,
        categories: [String]
    ) {
        self.customerId = customerId
        self.customerExternalId = customerExternalId
        self.crmSiteCode = crmSiteCode
        self.token = token
        self.fid = fid
        self.type = firebaseProjectId
        self.deviceType = "ios"
        self.categories = categories
    }
}
