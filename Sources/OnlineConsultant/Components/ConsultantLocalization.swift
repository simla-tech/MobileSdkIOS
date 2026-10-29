import Foundation

package enum ConsultantLocalization: String {

    case attachmentActionCamera = "attachment.action.camera"
    case attachmentActionCancel = "attachment.action.cancel"
    case attachmentActionPhotoOrVideo = "attachment.action.photo_or_video"
    case attachmentErrorCameraMissingUsageDescription = "attachment.error.camera_missing_usage_description"
    case attachmentErrorCameraUnavailable = "attachment.error.camera_unavailable"
    case attachmentErrorEmptyImageData = "attachment.error.empty_image_data"
    case attachmentErrorFileTooLarge = "attachment.error.file_too_large"
    case attachmentErrorImageTooLarge = "attachment.error.image_too_large"
    case attachmentErrorOperationFailed = "attachment.error.operation_failed"
    case attachmentErrorRetryUploadFailed = "attachment.error.retry_upload_failed"
    case attachmentErrorTooManyAttachments = "attachment.error.too_many_attachments"
    case attachmentFileExtensionFallback = "attachment.file_extension.fallback"
    case attachmentStatusLoading = "attachment.status.loading"

    case commonError = "common.error"
    case commonFile = "common.file"
    case commonOff = "common.off"
    case commonOk = "common.ok"
    case commonOn = "common.on"
    case commonRetry = "common.retry"
    case commonUnavailable = "common.unavailable"

    case contactFormDefaultText = "contact_form.default_text"
    case contactFormFieldComment = "contact_form.field.comment"
    case contactFormFieldEmail = "contact_form.field.email"
    case contactFormFieldName = "contact_form.field.name"
    case contactFormFieldPhone = "contact_form.field.phone"
    case contactFormMarketingConsent = "contact_form.marketing_consent"
    case contactFormPersonalDataConsent = "contact_form.personal_data_consent"
    case contactFormPersonalDataLinkText = "contact_form.personal_data_link_text"
    case contactFormSubmit = "contact_form.submit"
    case contactFormSubmitted = "contact_form.submitted"

    case clientErrorHTTPStatus = "client.error.http_status"
    case clientErrorMissingCredentials = "client.error.missing_credentials"
    case clientErrorRequestFailed = "client.error.request_failed"

    case controllerErrorInputAttachmentRemoved = "controller.error.input_attachment_removed"
    case controllerErrorInputAttachmentsNotUploaded = "controller.error.input_attachments_not_uploaded"
    case controllerErrorMissingCredentials = "controller.error.missing_credentials"
    case controllerErrorMissingUploadedFileID = "controller.error.missing_uploaded_file_id"
    case controllerErrorNotConnected = "controller.error.not_connected"
    case controllerErrorUnavailable = "controller.error.unavailable"

    case footerMadeIn = "footer.made_in"

    case fileCacheErrorEmptyFileID = "file_cache.error.empty_file_id"
    case fileCacheErrorMissingEntry = "file_cache.error.missing_entry"
    case fileCacheErrorOperationFailed = "file_cache.error.operation_failed"
    case unexpectedError = "consultant.error.unexpected"

    case messageActionCopy = "message.action.copy"
    case messageActionRetry = "message.action.retry"
    case messageAgreementFirst = "message.agreement.first"
    case messageAgreementLink = "message.agreement.link"
    case messageAgreementThird = "message.agreement.third"
    case messageAuthorBotAssistant = "message.author.bot_assistant"
    case messageAuthorConsultant = "message.author.consultant"
    case messageAuthorConsultantInitial = "message.author.consultant_initial"
    case messageAuthorVisitor = "message.author.visitor"
    case messageDateToday = "message.date.today"
    case messageDateYesterday = "message.date.yesterday"
    case messageDateFormat = "message.date.format"
    case messageDateYearFormat = "message.date.year_format"
    case messageInputPlaceholder = "message.input.placeholder"
    case messageQuoteAuthorYou = "message.quote.author_you"
    case messageQuotePlaceholder = "message.quote.placeholder"
    case messageQuoteUnavailable = "message.quote.unavailable"
    case messageQuotePhoto = "message.quote.photo"
    case messageItemImage = "message.item.image"
    case messageItemProduct = "message.item.product"

    case offlineDefaultText = "offline.default_text"
    case offlineFormDefaultResultText = "offline.form_default_result_text"

    case orderFieldAddress = "order.field.address"
    case orderFieldComment = "order.field.comment"
    case orderFieldDelivery = "order.field.delivery"
    case orderFieldDeliveryCost = "order.field.delivery_cost"
    case orderFieldDiscount = "order.field.discount"
    case orderFieldPayment = "order.field.payment"
    case orderFieldTotal = "order.field.total"
    case orderLabelNumber = "order.label.number"

    case productQuantityAvailable = "product.quantity.available"
    case productQuantityUnavailable = "product.quantity.unavailable"

    package var localized: String {
        NSLocalizedString(
            rawValue,
            bundle: .module,
            comment: ""
        )
    }

    package func format(_ arguments: CVarArg...) -> String {
        String(format: localized, arguments: arguments)
    }
}
