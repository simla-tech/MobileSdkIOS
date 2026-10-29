import Core
import Foundation

package struct TrackerEvent: Codable, Equatable, Sendable {
    package let id: String
    package let type: String
    package let code: String?
    package let data: [String: TrackerEventDataValue]?
    package let pageURL: String?
    package let pageTitle: String?
    package let referrerURL: String?
    package let timestamp: String
    package let createCustomer: Bool?
    package let createCustomerByEmail: Bool?
    package let systemCustomerID: Int64?
    package let systemCustomerExternalID: String?
    package let utm: CrmUtmAttribution?
    package let platform: String

    package init(
        id: String = UUID().uuidString.lowercased(),
        type: String,
        code: String? = nil,
        data: [String: TrackerEventDataValue]? = nil,
        pageURL: String? = nil,
        pageTitle: String? = nil,
        referrerURL: String? = nil,
        timestamp: String = TrackerEventTimestamp.make(),
        createCustomer: Bool? = nil,
        createCustomerByEmail: Bool? = nil,
        systemCustomerID: Int64? = nil,
        systemCustomerExternalID: String? = nil,
        platform: String = "ios",
        utm: CrmUtmAttribution? = nil
    ) {
        self.id = id
        self.type = type
        self.code = code?.nilIfEmpty
        self.data = data?.isEmpty == true ? nil : data
        self.pageURL = pageURL?.nilIfEmpty
        self.pageTitle = pageTitle?.nilIfEmpty
        self.referrerURL = referrerURL?.nilIfEmpty
        self.timestamp = timestamp
        self.createCustomer = createCustomer
        self.createCustomerByEmail = createCustomerByEmail
        self.systemCustomerID = systemCustomerID
        self.systemCustomerExternalID = systemCustomerExternalID?.nilIfEmpty
        self.platform = platform
        self.utm = utm
    }

    package func attributedIfAnonymous(
        systemCustomerID: Int64?,
        systemCustomerExternalID: String?
    ) -> TrackerEvent {
        guard self.systemCustomerID == nil || self.systemCustomerExternalID == nil else {
            return self
        }
        return TrackerEvent(
            id: id,
            type: type,
            code: code,
            data: data,
            pageURL: pageURL,
            pageTitle: pageTitle,
            referrerURL: referrerURL,
            timestamp: timestamp,
            createCustomer: createCustomer,
            createCustomerByEmail: createCustomerByEmail,
            systemCustomerID: self.systemCustomerID ?? systemCustomerID,
            systemCustomerExternalID: self.systemCustomerExternalID ?? systemCustomerExternalID,
            platform: platform,
            utm: utm
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case code
        case data
        case pageURL = "page_url"
        case pageTitle = "page_title"
        case referrerURL = "referrer_url"
        case timestamp
        case createCustomer = "create_customer"
        case createCustomerByEmail = "create_customer_by_email"
        case systemCustomerID = "system_customer_id"
        case systemCustomerExternalID = "system_customer_external_id"
        case utm
        case platform
    }
}
