import Foundation
import Core

/// Registers push identifiers in the client API.
///
/// `PushTokenRegistrator` is a package-scoped transport component used by `PushService`. It sends FCM
/// tokens or Firebase installation IDs to `/push-tokens` with the configured site token.
package struct PushTokenRegistrator: Sendable {

    private let session: URLSession
    private let clientAPIEndpointURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a registrator with a URL session configured from request timeouts.
    package init(
        session: URLSession = NetworkSession.shared,
        clientAPIEndpointURL: URL = APIEndpoints().clientAPIEndpointURL
    ) {
        self.clientAPIEndpointURL = clientAPIEndpointURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.session = session
    }

    /// Registers one push identifier for the provided customer and Firebase project.
    package func registerToken(
        _ token: PushToken,
        customerIdentity: CrmSdkCustomerIdentity,
        siteToken: String,
        firebaseProjectId: String,
        categories: [String],
        completion: @escaping (Result<PushToken, PushServiceError>) -> Void
    ) {
        let requestBody = PushTokenRequestBody(
            customerId: customerIdentity.customerId,
            customerExternalId: customerIdentity.siteCustomerId,
            crmSiteCode: customerIdentity.siteCode,
            token: token.fcmValue,
            fid: token.fidValue,
            firebaseProjectId: firebaseProjectId,
            categories: categories
        )

        var request = URLRequest(
            url: clientAPIEndpointURL.appendingPathComponent("push-tokens")
        )
        request.httpMethod = "POST"
        do {
            request.httpBody = try encoder.encode(requestBody)
        } catch {
            completion(.failure(.requestEncodingFailed(error.localizedDescription)))
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(siteToken, forHTTPHeaderField: "X-Site-Token")

        let task = NetworkSession.dataTask(
            with: request, in: session
        ) { [decoder] data, response, error in
            if let error {
                completion(.failure(.requestFailed(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidHTTPResponse(String(describing: response))))
                return
            }

            guard httpResponse.statusCode == 204 else {
                let messages = HTTPErrorResponseParser.messages(
                    from: data ?? Data(), fallbackForEmptyMessages: true
                ) { (try? decoder.decode(PushServiceErrorResponse.self, from: $0))?.errors }
                completion(.failure(.httpStatus(httpResponse.statusCode, messages)))
                return
            }

            completion(.success(token))
        }
        task.resume()
    }
}

private struct PushServiceErrorResponse: Decodable {
    let errors: [String]
}
