//
//  InputAttachmentStatus.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Upload state for a file selected in the message input.
 package enum InputAttachmentStatus: Equatable, Sendable {

    /// File upload is still in progress.
    case uploading

    /// File upload has completed and backend returned a file identifier.
    case uploaded(fileID: FlexibleID)

    /// File upload failed with a user-facing error message.
    case failed(message: String)

    /// Uploaded backend file identifier, if this status is `uploaded`.
     package var uploadedFileID: FlexibleID? {
        if case .uploaded(let fileID) = self {
            return fileID
        }

        return nil
    }
}
