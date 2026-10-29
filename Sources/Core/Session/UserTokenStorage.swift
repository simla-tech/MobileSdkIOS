import CryptoKit
import Foundation
import Security

/// Storage for the backend user token returned by `POST /connect`.
package protocol UserTokenStorage: AnyObject {

    /// Returns the token saved for a site and customer identity.
    func getUserToken(
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws -> String?

    /// Saves or removes the token for a site and customer identity.
    func setUserToken(
        _ token: String?,
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws
}

/// Keychain-backed storage that isolates tokens by site and customer identity.
package final class KeychainUserTokenStorage: UserTokenStorage {
    private static let service = "com.retailcrm.consultant-sdk.user-token"

    package init() {}

    package func getUserToken(
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws -> String? {
        var query = baseQuery(
            siteToken: siteToken,
            customerIdentity: customerIdentity
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let token = String(data: data, encoding: .utf8)
            else {
                throw CoreError.keychainInvalidTokenData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw CoreError.keychainUnexpectedStatus(status)
        }
    }

    package func setUserToken(
        _ token: String?,
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) throws {
        let query = baseQuery(
            siteToken: siteToken,
            customerIdentity: customerIdentity
        )

        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CoreError.keychainUnexpectedStatus(status)
            }
            return
        }

        let tokenData = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: tokenData] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CoreError.keychainUnexpectedStatus(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = tokenData
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CoreError.keychainUnexpectedStatus(addStatus)
        }
    }

    private func baseQuery(
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account(
                siteToken: siteToken,
                customerIdentity: customerIdentity
            )
        ]
    }

    private func account(
        siteToken: String,
        customerIdentity: CrmSdkCustomerIdentity?
    ) -> String {
        let components: [String]

        if let customerIdentity, let customerId = customerIdentity.customerId {
            components = [
                "customer-id",
                siteToken,
                String(customerId),
                customerIdentity.siteCode ?? "",
                customerIdentity.siteCustomerId ?? ""
            ]
        } else if let customerIdentity {
            components = [
                "customer",
                siteToken,
                customerIdentity.siteCode ?? "",
                customerIdentity.siteCustomerId ?? ""
            ]
        } else {
            components = ["anonymous", siteToken]
        }

        let scopeData = components.reduce(into: Data()) { data, component in
            data.append(contentsOf: component.utf8)
            data.append(0)
        }
        return SHA256.hash(data: scopeData)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
