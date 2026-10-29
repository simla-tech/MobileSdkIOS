import Core
import Foundation
import Tracker

/// Loads product recommendations and records interactions through the shared tracker.
public final class Recommendations {
    private let sessionRuntime: SessionRuntime
    private let tracker: Tracker
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Forwards shared tracker preparation updates on the main thread.
    /// Assigning this handler replaces Tracker.onReadyUpdate; nil clears the shared handler.
    public var onReadyUpdate: ((Bool, TrackerError?) -> Void)? {
        get { tracker.onReadyUpdate }
        set { tracker.onReadyUpdate = newValue }
    }

    /// Current tracking consent. The application persists and restores this decision.
    public var consentState: TrackerConsentState { tracker.consentState }

    /// Forwards tracker queue and delivery updates to the assigned handler.
    /// Assigning this handler replaces `Tracker.onEventUpdate` because both use the shared tracker.
    @MainActor public var onEventUpdate: ((TrackerEventUpdate) -> Void)? {
        get { tracker.onEventUpdate }
        set { tracker.onEventUpdate = newValue }
    }

    package convenience init(sessionRuntime: SessionRuntime, tracker: Tracker) {
        self.init(
            sessionRuntime: sessionRuntime,
            tracker: tracker,
            session: NetworkSession.shared
        )
    }

    package init(sessionRuntime: SessionRuntime, tracker: Tracker, session: URLSession) {
        self.sessionRuntime = sessionRuntime
        self.tracker = tracker
        self.session = session
    }

    /// Applies the user's tracking decision to the shared tracker.
    ///
    /// - Parameters:
    ///   - consent: User tracking decision shared with the Tracker module.
    @discardableResult
    public func setConsent(_ consent: RecommendationsConsentState) -> Result<Void, RecommendationsError> {
        let trackerConsent: TrackerConsentState = {
            switch consent {
            case .unknown: .unknown
            case .granted: .granted
            case .denied: .denied
            }
        }()
        return tracker.setConsent(trackerConsent).mapError(RecommendationsError.from)
    }

    /// Loads a product recommendation selection. An empty selection is a successful result.
    ///
    /// Uses the customer identity from the shared SDK session.
    ///
    /// - Parameters:
    ///   - requestBody: Recommendation mechanic and optional product or offer context.
    public func getProducts(_ requestBody: ProductRecommendationsRequest) async throws -> ProductRecommendations {
        do {
            try requestBody.validate()
            let context = try await sessionRuntime.authorizedRequestContext()
            var request = URLRequest(url: endpointURL("recommendations/products"))
            request.httpMethod = "POST"
            context.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.httpBody = try encoder.encode(
                ProductRecommendationsRequestBody(request: requestBody, customerIdentity: context.customerIdentity)
            )

            let (data, response) = try await NetworkSession.data(
                for: request,
                in: session
            )
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let messages = (try? decoder.decode(ErrorResponse.self, from: data).errors) ?? []
                throw RecommendationsError.httpStatus(statusCode, messages)
            }

            return try decoder.decode(ProductRecommendations.self, from: data)
        } catch {
            throw RecommendationsError.from(error)
        }
    }

    /// Records a visible recommendation block and returns its queued tracker event ID.
    ///
    /// - Parameters:
    ///   - recommendation: Recommendation selection whose execution ID identifies the event.
    ///   - screenURI: Absolute URI of the screen where the event occurred.
    ///   - title: Optional title of the screen showing the recommendations.
    public func trackImpression(
        _ recommendation: ProductRecommendations,
        screenURI: String,
        title: String? = nil
    ) async throws -> String {
        do {
            try Task.checkCancellation()
            guard recommendation.executionID > 0 else {
                throw RecommendationsError.invalidRequest(RecommendationsLocalization.executionIDInvalid.localized)
            }
            let uri = screenURI.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: uri), url.scheme != nil else {
                throw RecommendationsError.invalidRequest(RecommendationsLocalization.screenURIInvalid.localized)
            }
            let result = await withCheckedContinuation { continuation in
                tracker.trackRecommendationImpression(
                    executionID: recommendation.executionID,
                    screenURI: uri,
                    title: title,
                    completion: { continuation.resume(returning: $0) }
                )
            }
            return try result.get()
        } catch let error as TrackerError {
            throw RecommendationsError.from(error)
        } catch {
            throw RecommendationsError.from(error)
        }
    }

    /// Records a product click and returns its queued tracker event ID.
    ///
    /// - Parameters:
    ///   - recommendation: Recommendation selection whose execution ID identifies the event.
    ///   - productID: Internal ID of the clicked recommended product.
    ///   - position: Optional zero-based position of the clicked product.
    ///   - element: Optional identifier of the clicked UI element.
    ///   - leaving: Whether selecting the product leaves the current screen.
    public func trackClick(
        _ recommendation: ProductRecommendations,
        productID: Int64,
        position: Int? = nil,
        element: String? = nil,
        leaving: Bool = false
    ) async throws -> String {
        do {
            try Task.checkCancellation()
            guard recommendation.executionID > 0 else {
                throw RecommendationsError.invalidRequest(RecommendationsLocalization.executionIDInvalid.localized)
            }
            guard productID > 0, productID <= Int64(UInt32.max) else {
                throw RecommendationsError.invalidRequest(RecommendationsLocalization.clickProductIDInvalid.localized)
            }
            if let position, !(0...Int(UInt32.max)).contains(position) {
                throw RecommendationsError.invalidRequest(RecommendationsLocalization.positionInvalid.localized)
            }
            let result = await withCheckedContinuation { continuation in
                tracker.trackRecommendationClick(
                    executionID: recommendation.executionID,
                    productID: productID,
                    position: position,
                    element: element,
                    leaving: leaving,
                    completion: { continuation.resume(returning: $0) }
                )
            }
            return try result.get()
        } catch let error as TrackerError {
            throw RecommendationsError.from(error)
        } catch {
            throw RecommendationsError.from(error)
        }
    }

    private func endpointURL(_ path: String) -> URL {
        path.split(separator: "/").reduce(sessionRuntime.config.endpoints.clientAPIEndpointURL) {
            $0.appendingPathComponent(String($1))
        }
    }

    private struct ErrorResponse: Decodable {
        let errors: [String]
    }
}

/// Completion-based API for callers that do not use Swift concurrency.
public extension Recommendations {

    /// Loads a product recommendation selection and reports the result on the main thread.
    ///
    /// - Parameters:
    ///   - requestBody: Recommendation mechanic and optional customer or product context.
    ///   - completion: Receives the selection or a recommendation error on the main thread.
    func getProducts(
        _ requestBody: ProductRecommendationsRequest,
        completion: @escaping (Result<ProductRecommendations, RecommendationsError>) -> Void
    ) {
        Task {
            let result: Result<ProductRecommendations, RecommendationsError>
            do { result = .success(try await getProducts(requestBody)) }
            catch { result = .failure(RecommendationsError.from(error)) }
            await MainActor.run { completion(result) }
        }
    }

    /// Records a displayed recommendation block and reports its queued tracker event ID.
    /// The completion runs on the main thread.
    ///
    /// - Parameters:
    ///   - recommendation: Recommendation selection whose execution ID identifies the event.
    ///   - screenURI: Absolute URI of the screen where the event occurred.
    ///   - title: Optional title of the screen showing the recommendations.
    ///   - completion: Receives the queued event ID or an error on the main thread.
    func trackImpression(
        _ recommendation: ProductRecommendations,
        screenURI: String,
        title: String? = nil,
        completion: @escaping (Result<String, RecommendationsError>) -> Void
    ) {
        Task {
            let result: Result<String, RecommendationsError>
            do { result = .success(try await trackImpression(recommendation, screenURI: screenURI, title: title)) }
            catch { result = .failure(RecommendationsError.from(error)) }
            await MainActor.run { completion(result) }
        }
    }

    /// Records a click on a recommended product and reports its queued tracker event ID.
    /// The completion runs on the main thread.
    ///
    /// - Parameters:
    ///   - recommendation: Recommendation selection whose execution ID identifies the event.
    ///   - productID: Internal ID of the clicked recommended product.
    ///   - position: Optional zero-based position of the clicked product.
    ///   - element: Optional identifier of the clicked UI element.
    ///   - leaving: Whether selecting the product leaves the current screen.
    ///   - completion: Receives the queued event ID or an error on the main thread.
    func trackClick(
        _ recommendation: ProductRecommendations,
        productID: Int64,
        position: Int? = nil,
        element: String? = nil,
        leaving: Bool = false,
        completion: @escaping (Result<String, RecommendationsError>) -> Void
    ) {
        Task {
            let result: Result<String, RecommendationsError>
            do {
                result = .success(try await trackClick(
                    recommendation, productID: productID, position: position,
                    element: element, leaving: leaving
                ))
            } catch {
                result = .failure(RecommendationsError.from(error))
            }
            await MainActor.run { completion(result) }
        }
    }
}
