import Foundation

/// Errors exposed by the OnlineConsultant module.
public enum ConsultantError: Error, Equatable, LocalizedError, Sendable {
    /// Failures of consultant network requests.
    public enum ClientFailure: Equatable, Sendable {
        /// The connection response omitted its credentials.
        case missingConnectionCredentials
        /// The server returned an HTTP status and optional messages.
        case httpStatus(Int, [String])
        /// The request failed before a usable response was received.
        case requestFailed(String)
    }

    /// Failures of chat state and message operations.
    public enum ControllerFailure: Equatable, Sendable {
        /// A connected session is required.
        case notConnected
        /// Session credentials are missing.
        case missingCredentials
        /// The consultant is unavailable.
        case unavailable
        /// An upload response omitted the file identifier.
        case missingUploadedFileID
        /// Message attachments have not finished uploading.
        case inputAttachmentsNotReady
    }

    /// Failures of the local file cache.
    public enum FileCacheFailure: Equatable, Sendable {
        /// The file identifier is empty.
        case emptyFileID
        /// No cache entry exists for the file identifier.
        case missingEntry(fileID: String)
        /// A cache operation failed for another reason.
        case operationFailed(String)
    }

    /// Failures of selecting or preparing attachments.
    public enum AttachmentFailure: Equatable, Sendable {
        /// Image data could not be read.
        case emptyImageData
        /// The image exceeds the upload size limit.
        case imageTooLarge
        /// The file exceeds the upload size limit.
        case fileTooLarge
        /// The attachment count exceeds the input limit.
        case tooManyAttachments
        /// An attachment operation failed for another reason.
        case operationFailed(String)
    }

    /// A consultant network request failed.
    case client(ClientFailure)
    /// A chat controller operation failed.
    case controller(ControllerFailure)
    /// A local cache operation failed.
    case fileCache(FileCacheFailure)
    /// An attachment operation failed.
    case attachment(AttachmentFailure)
    /// An operation failed with an unclassified error.
    case unexpected(String)

    /// Localized human-readable error description.
    public var errorDescription: String? {
        switch self {
        case .client(.missingConnectionCredentials):
            return ConsultantLocalization.clientErrorMissingCredentials.localized
        case .client(.httpStatus(let statusCode, let messages)):
            let description = ConsultantLocalization.clientErrorHTTPStatus.format(statusCode)
            return messages.isEmpty ? description : description + " " + messages.joined(separator: " ")
        case .client(.requestFailed(let message)):
            return ConsultantLocalization.clientErrorRequestFailed.format(message)
        case .controller(.notConnected):
            return ConsultantLocalization.controllerErrorNotConnected.localized
        case .controller(.missingCredentials):
            return ConsultantLocalization.controllerErrorMissingCredentials.localized
        case .controller(.unavailable):
            return ConsultantLocalization.controllerErrorUnavailable.localized
        case .controller(.missingUploadedFileID):
            return ConsultantLocalization.controllerErrorMissingUploadedFileID.localized
        case .controller(.inputAttachmentsNotReady):
            return ConsultantLocalization.controllerErrorInputAttachmentsNotUploaded.localized
        case .fileCache(.emptyFileID):
            return ConsultantLocalization.fileCacheErrorEmptyFileID.localized
        case .fileCache(.missingEntry(let fileID)):
            return ConsultantLocalization.fileCacheErrorMissingEntry.format(fileID)
        case .attachment(.emptyImageData):
            return ConsultantLocalization.attachmentErrorEmptyImageData.localized
        case .attachment(.imageTooLarge):
            return ConsultantLocalization.attachmentErrorImageTooLarge.localized
        case .attachment(.fileTooLarge):
            return ConsultantLocalization.attachmentErrorFileTooLarge.localized
        case .attachment(.tooManyAttachments):
            return ConsultantLocalization.attachmentErrorTooManyAttachments.localized
        case .fileCache(.operationFailed(let message)):
            return ConsultantLocalization.fileCacheErrorOperationFailed.format(message)
        case .attachment(.operationFailed(let message)):
            return ConsultantLocalization.attachmentErrorOperationFailed.format(message)
        case .unexpected(let message):
            return ConsultantLocalization.unexpectedError.format(message)
        }
    }
}

package extension ConsultantError {
    static func cacheError(from error: Error) -> Self {
        let converted = from(error)
        if case .fileCache = converted { return converted }
        return .fileCache(.operationFailed(error.localizedDescription))
    }

    static func from(_ error: Error) -> Self {
        if let error = error as? Self { return error }

        if let error = error as? ConsultantControllerError {
            switch error {
            case .notConnected: return .controller(.notConnected)
            case .missingCredentials: return .controller(.missingCredentials)
            case .unavailable: return .controller(.unavailable)
            case .missingUploadedFileID: return .controller(.missingUploadedFileID)
            case .inputAttachmentsNotReady: return .controller(.inputAttachmentsNotReady)
            case .inputAttachmentRemoved: return .unexpected(error.localizedDescription)
            }
        }

        if let error = error as? ConsultantClientError {
            switch error {
            case .missingConnectionCredentials: return .client(.missingConnectionCredentials)
            case .httpStatus(let statusCode, let messages):
                return .client(.httpStatus(statusCode, messages))
            case .requestFailed(let message): return .client(.requestFailed(message))
            }
        }

        if let error = error as? ConsultantFileCacheError {
            switch error {
            case .emptyFileID: return .fileCache(.emptyFileID)
            case .missingEntry(let fileID): return .fileCache(.missingEntry(fileID: fileID))
            }
        }

        if let error = error as? AttachmentPickerError {
            switch error {
            case .emptyImageData: return .attachment(.emptyImageData)
            case .imageTooLarge: return .attachment(.imageTooLarge)
            case .fileTooLarge: return .attachment(.fileTooLarge)
            case .tooManyAttachments: return .attachment(.tooManyAttachments)
            }
        }

        return .unexpected(error.localizedDescription)
    }
}
