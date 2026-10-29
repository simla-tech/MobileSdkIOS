import Foundation

/// Shares page requests between normal pagination and quote navigation.
@MainActor
package final class MessageHistoryCoordinator {
    private let messages: () -> [ConsultantMessage]
    private let canLoadMore: () -> Bool
    private let loadPage: () async throws -> MessagesPage
    private var pageTask: Task<MessagesPage, Error>?
    private var pageRequestID: UUID?

    package init(
        messages: @escaping () -> [ConsultantMessage],
        canLoadMore: @escaping () -> Bool,
        loadPage: @escaping () async throws -> MessagesPage
    ) {
        self.messages = messages
        self.canLoadMore = canLoadMore
        self.loadPage = loadPage
    }

    deinit { pageTask?.cancel() }

    package func cancel() {
        pageTask?.cancel()
        pageTask = nil
        pageRequestID = nil
    }

    package func loadNextPage() async throws -> MessagesPage {
        if let pageTask { return try await pageTask.value }
        let requestID = UUID()
        let loader = loadPage
        let task = Task { try await loader() }
        pageTask = task
        pageRequestID = requestID
        defer {
            if pageRequestID == requestID {
                pageTask = nil
                pageRequestID = nil
            }
        }
        return try await task.value
    }

    /// Loads older pages until the target is found or history is exhausted.
    package func findMessage(id: String) async throws -> Bool {
        while true {
            try Task.checkCancellation()
            if messages().contains(where: { $0.id?.value == id && $0.status != .deleted }) { return true }
            guard canLoadMore() else { return false }
            let knownIDs = Set(messages().compactMap { $0.id?.value })
            let page = try await loadNextPage()
            try Task.checkCancellation()
            if messages().contains(where: { $0.id?.value == id && $0.status != .deleted }) { return true }
            guard page.hasMoreMessages, !page.messages.isEmpty,
                  Set(messages().compactMap { $0.id?.value }) != knownIDs else { return false }
        }
    }
}
