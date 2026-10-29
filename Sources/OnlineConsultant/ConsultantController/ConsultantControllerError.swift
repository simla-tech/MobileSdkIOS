//
//  ConsultantControllerError.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 23.07.2026.
//

import Foundation

/// Domain errors produced by `OnlineConsultantController` before or around backend calls.
///
/// Covers local validation failures such as missing connection credentials, unavailable consultant
/// configuration, incomplete upload responses, and input attachments that cannot be sent yet. Each
/// case also provides a user-readable localized description.
package enum ConsultantControllerError: Error, Equatable, LocalizedError {

    /// Operation requires an active consultant connection.
    case notConnected
    /// Connect response does not contain required session credentials.
    case missingCredentials
    /// Backend configuration says that the consultant is unavailable.
    case unavailable
    /// File upload response does not contain a backend file id.
    case missingUploadedFileID
    /// Message attachments are not uploaded yet.
    case inputAttachmentsNotReady
    /// Attachment was removed before upload finished.
    case inputAttachmentRemoved

    /// User-readable error description.
    package var errorDescription: String? {
        switch self {
        case .notConnected:
            return ConsultantLocalization.controllerErrorNotConnected.localized
        case .missingCredentials:
            return ConsultantLocalization.controllerErrorMissingCredentials.localized
        case .unavailable:
            return ConsultantLocalization.controllerErrorUnavailable.localized
        case .missingUploadedFileID:
            return ConsultantLocalization.controllerErrorMissingUploadedFileID.localized
        case .inputAttachmentsNotReady:
            return ConsultantLocalization.controllerErrorInputAttachmentsNotUploaded.localized
        case .inputAttachmentRemoved:
            return ConsultantLocalization.controllerErrorInputAttachmentRemoved.localized
        }
    }
}
