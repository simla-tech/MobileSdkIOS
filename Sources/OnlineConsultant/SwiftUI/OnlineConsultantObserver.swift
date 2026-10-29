import Combine
import Core
import SwiftUI

/// Observable adapter that publishes state from an `OnlineConsultantController` to SwiftUI.
@MainActor
public final class OnlineConsultantObserver: ObservableObject {

    /// Chat controller observed by this adapter.
    public let onlineConsultant: OnlineConsultantController

    /// Current connection state.
    @Published public private(set) var state: ControllerState
    /// Number of unread incoming messages in the loaded history; zero when the counter is disabled.
    @Published public private(set) var unreadIncomingMessagesCount: Int
    /// Chat title received from backend `config.name`.
    @Published public private(set) var name: String?
    /// External consultant link settings received from the backend.
    @Published public private(set) var linkSettings: LinkSettings
    /// Local file-cache statistics from the last refresh or cache operation.
    @Published public private(set) var cacheStatistics: ConsultantCacheStatistics

    private var observationTasks: [Task<Void, Never>] = []

    /// Creates an observable adapter around an existing online consultant.
    ///
    /// - Parameters:
    ///   - onlineConsultant: Chat controller whose state the observer publishes.
    public init(onlineConsultant: OnlineConsultantController) {
        self.onlineConsultant = onlineConsultant
        self.state = onlineConsultant.state
        self.unreadIncomingMessagesCount = onlineConsultant.unreadIncomingMessagesCount
        self.name = onlineConsultant.name
        self.linkSettings = onlineConsultant.linkSettings
        self.cacheStatistics = onlineConsultant.cacheStatistics()
        startObservingController()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }
}

// MARK: - Controller API

public extension OnlineConsultantObserver {

    /// Refreshes published local file-cache statistics.
    func refreshCacheStatistics() {
        cacheStatistics = onlineConsultant.cacheStatistics()
    }

    /// Applies the configured cache policy and publishes the updated statistics.
    func trimCache() async throws -> ConsultantCacheStatistics {
        let statistics = try await onlineConsultant.trimCache()
        cacheStatistics = statistics
        return statistics
    }

    /// Clears the local file cache and refreshes published statistics.
    func clearCache() async throws {
        try await onlineConsultant.clearCache()
        refreshCacheStatistics()
    }

    /// Forwards the controller's handler; assignment immediately reports its current state.
    var onStateChange: ((ControllerState) -> Void)? {
        get { onlineConsultant.onStateChange }
        set { onlineConsultant.onStateChange = newValue }
    }

    /// Forwards the controller's handler; assignment immediately reports its current unread count.
    var onUnreadIncomingMessagesCountChange: ((Int) -> Void)? {
        get { onlineConsultant.onUnreadIncomingMessagesCountChange }
        set { onlineConsultant.onUnreadIncomingMessagesCountChange = newValue }
    }
}

/// Completion-based file-cache API.
public extension OnlineConsultantObserver {

    /// Applies the configured cache policy and returns statistics in the completion.
    ///
    /// - Parameter completion: Receives the updated cache statistics or a cache error.
    func trimCache(
        completion: (Result<ConsultantCacheStatistics, ConsultantError>) -> Void
    ) {
        onlineConsultant.trimCache { result in
            if case .success(let statistics) = result {
                cacheStatistics = statistics
            }
            completion(result)
        }
    }

    /// Clears all locally cached files managed by the SDK.
    ///
    /// - Parameter completion: Receives the cache cleanup result.
    func clearCache(completion: (Result<Void, ConsultantError>) -> Void) {
        onlineConsultant.clearCache { result in
            if case .success = result {
                refreshCacheStatistics()
            }
            completion(result)
        }
    }
}

// MARK: - Observation

private extension OnlineConsultantObserver {

    func startObservingController() {
        let onlineConsultant = onlineConsultant
        let events = onlineConsultant.events()
        observationTasks = [
            Task { [weak self] in
                for await state in onlineConsultant.stateUpdates() {
                    guard !Task.isCancelled else { return }
                    self?.state = state
                    self?.refreshConfigurationState()
                }
            },
            Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { return }
                    if case .unreadIncomingMessagesCountChanged(let count) = event {
                        self?.unreadIncomingMessagesCount = count
                    }
                }
            },
            Task { [weak self] in
                for await _ in onlineConsultant.internalStateUpdates() {
                    guard !Task.isCancelled else { return }
                    self?.refreshConfigurationState()
                }
            }
        ]
    }

    func refreshConfigurationState() {
        name = onlineConsultant.name
        linkSettings = onlineConsultant.linkSettings
    }
}
