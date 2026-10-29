import Core
import Foundation

/// Coordinator for resolving message attachment file links.
///
/// Converts backend file item identifiers into usable URLs by checking the local file cache, reusing
/// stored remote URLs, calling the backend file-link endpoint for missing data, and caching remote
/// files in the background. It also owns cancellation for file-link and remote-cache tasks.
@MainActor
package final class MessageFileLinkCoordinator {

    private let client: OnlineConsultantClient
    private let fileCache: ConsultantFileCache
    private let remoteFileCacheLoader: ConsultantRemoteFileCacheLoading
    private let cachePolicy: OnlineConsultantCachePolicy
    private var fileLinkTasks: [String: Task<Void, Never>] = [:]
    private var remoteFileCacheTasks: [String: Task<Void, Never>] = [:]
    private var fileLinkGeneration = UUID()

    /// Creates a coordinator for message file-link resolution and background caching.
    package init(
        client: OnlineConsultantClient,
        fileCache: ConsultantFileCache,
        remoteFileCacheLoader: ConsultantRemoteFileCacheLoading,
        cachePolicy: OnlineConsultantCachePolicy
    ) {
        self.client = client
        self.fileCache = fileCache
        self.remoteFileCacheLoader = remoteFileCacheLoader
        self.cachePolicy = cachePolicy
    }

    /// Resolves missing file links from local cache, stored remote URLs, and backend file-link API.
    package func resolveMissingFileLinks(
        unresolvedFileIDs: Set<String>,
        credentials: MessageFileLinkCredentials?,
        applyFileLinks: @escaping ([String: String]) -> Void,
        handleError: @escaping (Error) -> Void
    ) {
        var unresolvedFileIDs = unresolvedFileIDs
        guard !unresolvedFileIDs.isEmpty else {
            return
        }

        let localLinks = cachedLocalFileLinks(for: unresolvedFileIDs)
        applyFileLinksIfNeeded(
            localLinks,
            applyFileLinks: applyFileLinks
        )
        unresolvedFileIDs.subtract(localLinks.keys)

        let remoteLinks = cachedRemoteFileLinks(for: unresolvedFileIDs)
        applyFileLinksIfNeeded(
            remoteLinks,
            applyFileLinks: applyFileLinks
        )
        unresolvedFileIDs.subtract(remoteLinks.keys)
        cacheRemoteFileLinks(
            remoteLinks,
            applyFileLinks: applyFileLinks,
            handleError: handleError
        )

        loadMissingRemoteFileLinks(
            fileIDs: unresolvedFileIDs,
            credentials: credentials,
            applyFileLinks: applyFileLinks,
            handleError: handleError
        )
    }

    /// Cancels all active file-link and remote-file cache tasks.
    package func cancel() {
        fileLinkTasks.values.forEach { $0.cancel() }
        fileLinkTasks.removeAll()
        cancelRemoteCaching()
        fileLinkGeneration = UUID()
    }

    /// Cancels only background remote-file cache tasks.
    package func cancelRemoteCaching() {
        remoteFileCacheTasks.values.forEach { $0.cancel() }
        remoteFileCacheTasks.removeAll()
    }

    private func applyFileLinksIfNeeded(
        _ links: [String: String],
        applyFileLinks: ([String: String]) -> Void
    ) {
        guard !links.isEmpty else {
            return
        }

        applyFileLinks(links)
    }

    private func loadMissingRemoteFileLinks(
        fileIDs: Set<String>,
        credentials: MessageFileLinkCredentials?,
        applyFileLinks: @escaping ([String: String]) -> Void,
        handleError: @escaping (Error) -> Void
    ) {
        guard let credentials else {
            return
        }

        for fileID in fileIDs where fileLinkTasks[fileID] == nil {
            let generation = fileLinkGeneration
            fileLinkTasks[fileID] = Task { [weak self] in
                guard let self else { return }

                defer {
                    if fileLinkGeneration == generation {
                        fileLinkTasks[fileID] = nil
                    }
                }

                do {
                    let response = try await client.loadFileLink(
                        fileID: fileID,
                        session: credentials.sessionID,
                        userToken: credentials.userToken
                    )

                    guard
                        !Task.isCancelled,
                        fileLinkGeneration == generation,
                        let url = response.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                        !url.isEmpty
                    else {
                        return
                    }

                    persistRemoteFileLink(
                        itemID: fileID,
                        url: url,
                        handleError: handleError
                    )
                    applyFileLinks([fileID: url])
                    cacheRemoteFileLink(
                        itemID: fileID,
                        url: url,
                        applyFileLinks: applyFileLinks,
                        handleError: handleError
                    )
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    handleError(error)
                }
            }
        }
    }

    private func cachedLocalFileLinks(for fileIDs: Set<String>) -> [String: String] {
        fileIDs.reduce(into: [:]) { result, fileID in
            guard let localURL = fileCache.cachedFileURL(fileID: fileID) else {
                return
            }

            result[fileID] = localURL.absoluteString
        }
    }

    private func cachedRemoteFileLinks(for fileIDs: Set<String>) -> [String: String] {
        fileIDs.reduce(into: [:]) { result, fileID in
            guard let remoteURL = fileCache.entry(fileID: fileID)?.remoteURL else {
                return
            }

            result[fileID] = remoteURL.absoluteString
        }
    }

    private func persistRemoteFileLink(
        itemID: String,
        url: String,
        handleError: (Error) -> Void
    ) {
        guard let remoteURL = URL(string: url) else {
            return
        }

        do {
            try fileCache.updateRemoteURL(
                fileID: itemID,
                remoteURL: remoteURL
            )
        } catch {
            handleError(ConsultantError.cacheError(from: error))
        }
    }

    private func cacheRemoteFileLinks(
        _ links: [String: String],
        applyFileLinks: @escaping ([String: String]) -> Void,
        handleError: @escaping (Error) -> Void
    ) {
        links.forEach { itemID, url in
            cacheRemoteFileLink(
                itemID: itemID,
                url: url,
                applyFileLinks: applyFileLinks,
                handleError: handleError
            )
        }
    }

    private func cacheRemoteFileLink(
        itemID: String,
        url: String,
        applyFileLinks: @escaping ([String: String]) -> Void,
        handleError: @escaping (Error) -> Void
    ) {
        guard
            remoteFileCacheTasks[itemID] == nil,
            fileCache.cachedFileURL(fileID: itemID) == nil,
            let remoteURL = URL(string: url),
            !remoteURL.isFileURL
        else {
            return
        }

        let generation = fileLinkGeneration
        remoteFileCacheTasks[itemID] = Task { [weak self] in
            guard let self else { return }

            defer {
                if fileLinkGeneration == generation {
                    remoteFileCacheTasks[itemID] = nil
                }
            }

            do {
                let localURL = try await remoteFileCacheLoader.cacheRemoteFile(
                    fileID: itemID,
                    remoteURL: remoteURL
                )
                trimCacheIfNeeded(handleError: handleError)

                guard
                    !Task.isCancelled,
                    fileLinkGeneration == generation
                else {
                    return
                }
                applyFileLinks([itemID: localURL.absoluteString])
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                handleError(error)
            }
        }
    }

    private func trimCacheIfNeeded(handleError: (Error) -> Void) {
        guard cachePolicy.automaticCleanup else {
            return
        }

        do {
            _ = try fileCache.trim(policy: cachePolicy)
        } catch {
            handleError(ConsultantError.cacheError(from: error))
        }
    }
}

/// Credentials required by message file-link requests.
///
/// Keeps the current session id and user token together so the coordinator can call the authorized
/// backend file-link endpoint without depending on the full controller state.
package struct MessageFileLinkCredentials {

    /// Current consultant session identifier.
    package let sessionID: String

    /// Current consultant user token.
    package let userToken: String

    package init(sessionID: String, userToken: String) {
        self.sessionID = sessionID
        self.userToken = userToken
    }
}
