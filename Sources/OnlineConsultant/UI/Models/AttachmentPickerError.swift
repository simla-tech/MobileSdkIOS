//
//  OnlineConsultantAttachmentPickerError.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Foundation

/// User-facing errors produced while picking or preparing input attachments.
package enum AttachmentPickerError: LocalizedError {

    /// Picked image exists, but image data could not be read.
    case emptyImageData

    /// Picked image exceeds the SDK image upload size limit.
    case imageTooLarge

    /// Picked file exceeds the SDK file upload size limit.
    case fileTooLarge

    /// User selected more attachments than the input allows.
    case tooManyAttachments

    /// Localized message displayed in the attachment error alert.
    package var errorDescription: String? {
        switch self {
        case .emptyImageData:
            return ConsultantLocalization.attachmentErrorEmptyImageData.localized
        case .imageTooLarge:
            return ConsultantLocalization.attachmentErrorImageTooLarge.localized
        case .fileTooLarge:
            return ConsultantLocalization.attachmentErrorFileTooLarge.localized
        case .tooManyAttachments:
            return ConsultantLocalization.attachmentErrorTooManyAttachments.localized
        }
    }
}
