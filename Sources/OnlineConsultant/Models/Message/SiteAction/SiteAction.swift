//
//  SiteAction.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Foundation

/// Site action returned by the connect response.
///
/// Backend actions are configured for both the browser widget and mobile SDKs. The iOS SDK supports
/// immediate `contact_form` actions, including form content, image, retry state, mobile device
/// filtering, weekday filtering, and user-local time filtering. Browser-specific triggers are not
/// exposed by this model.
package struct SiteAction: Decodable, Equatable, Sendable {

    /// Action identifier used when marking the action as executed.
    package let id: FlexibleID?

    /// Backend action type.
    package let type: SiteActionType?

    /// Optional title displayed above the contact form.
    package let header: String?

    /// Message texts configured for the action.
    package let messages: [String]

    /// Contact form field configuration for `contact_form` actions.
    package let contactForm: [ContactFormFieldKey: ContactFormField]?

    /// Remote image URL or preinstalled image identifier attached to the contact form.
    package let image: String?

    /// Indicates whether the action can be executed again after a previous execution.
    private let allowRetry: Bool

    /// Last execution state for retryable actions.
    private let lastExecution: SiteActionExecution?

    /// Target device from backend `user_device`. iOS treats empty, `any`, and `mobile` as supported.
    private let userDevice: String?

    /// Weekday keys when the action is limited to specific local weekdays.
    private let weekdays: [String]

    /// Start of the supported local user-time interval in `HH:mm` format.
    private let userCurrentTimeFrom: String?

    /// End of the supported local user-time interval in `HH:mm` format.
    private let userCurrentTimeTo: String?

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(FlexibleID.self, forKey: .id)
        type = try container.decodeIfPresent(SiteActionType.self, forKey: .type)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        messages = try container.decodeIfPresent([String].self, forKey: .messages) ?? []
        contactForm = try container.decodeIfPresent(
            [String: ContactFormField].self,
            forKey: .contactForm
        ).map(Dictionary.init(backendFields:))
        image = try container.decodeIfPresent(String.self, forKey: .image)
        allowRetry = try container.decodeIfPresent(Bool.self, forKey: .allowRetry) ?? false
        lastExecution = try container.decodeIfPresent(SiteActionExecution.self, forKey: .lastExecution)
        userDevice = try container.decodeIfPresent(String.self, forKey: .userDevice)
        weekdays = try container.decodeIfPresent([String].self, forKey: .weekdays) ?? []
        userCurrentTimeFrom = try container.decodeIfPresent(String.self, forKey: .userCurrentTimeFrom)
        userCurrentTimeTo = try container.decodeIfPresent(String.self, forKey: .userCurrentTimeTo)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case header
        case messages
        case contactForm = "contact_form"
        case image
        case allowRetry = "allow_retry"
        case lastExecution = "last_execution"
        case userDevice = "user_device"
        case weekdays
        case userCurrentTimeFrom = "user_current_time_from"
        case userCurrentTimeTo = "user_current_time_to"
    }
}

package extension SiteAction {

    /// Resolved action image URL, either remote or bundled preinstalled resource.
    var imageURL: URL? {
        ActionImage.remoteURL(from: image)
            ?? actionImage?.preinstalledURL
    }

    /// Preinstalled image identifier when `image` points to a bundled action image.
    var imageID: String? {
        actionImage?.preinstalledID
    }

    /// Preinstalled bundled action image when `image` contains a known backend image id.
    var actionImage: ActionImage? {
        .init(preinstalledID: image)
    }

    /// Image items for a contact-form action.
    var messageItems: [MessageItem] {
        if let imageID {
            return [MessageItem(id: imageID)]
        }

        guard let imageURL = imageURL?.absoluteString.nilIfEmpty else {
            return []
        }

        return [MessageItem(url: imageURL)]
    }
}

package extension SiteAction {

    /// Indicates whether this action is a supported immediate contact form action.
    var isSafeImmediateContactFormAction: Bool {
        type == .contactForm
            && isAllowedByRetryPolicy
            && isAllowedForCurrentDevice
            && isAllowedForCurrentWeekday
            && isAllowedForCurrentUserTime
    }

    /// Contact form fields decoded from the backend `contact_form` object.
    var contactFormFields: [ContactFormFieldKey: ContactFormField] {
        contactForm ?? [:]
    }

    /// Returns whether the action still needs to show a contact form for the current user.
    func requiresContactForm(for user: ContactFormUser) -> Bool {
        guard isSafeImmediateContactFormAction else {
            return false
        }

        let fields = contactFormFields
        guard !fields.isEmpty else {
            return false
        }

        return fields.contains { field, config in
            switch field {
            case .personalData:
                return false
            case .marketingConsent:
                return config.required
            default:
                return config.required && !user.hasFilledValue(for: field)
            }
        }
    }

    /// Builds a local contact form model for a supported contact form action.
    func makeContactForm(for user: ContactFormUser) -> ContactForm? {
        guard requiresContactForm(for: user) else {
            return nil
        }

        return ContactForm(
            text: messages
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .nilIfEmpty,
            display: .atBeginningDialogue,
            fields: contactFormFields,
            prefill: ContactFormPrefill(
                name: user.name,
                email: user.email,
                phone: user.phone
            ),
            actionID: id
        )
    }

    private var isAllowedByRetryPolicy: Bool {
        lastExecution == nil || allowRetry
    }

    private var isAllowedForCurrentDevice: Bool {
        guard let value = userDevice else {
            return true
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedValue.isEmpty || normalizedValue == "any" || normalizedValue == "mobile"
    }

    private var isAllowedForCurrentWeekday: Bool {
        guard !weekdays.isEmpty else {
            return true
        }

        let weekdayNumbers = Set(weekdays.compactMap(\.weekdayNumber))
        guard !weekdayNumbers.isEmpty else {
            return false
        }

        return weekdayNumbers.contains(Calendar.current.component(.weekday, from: Date()) - 1)
    }

    private var isAllowedForCurrentUserTime: Bool {
        let fromValue = userCurrentTimeFrom?.timeMinutes
        let toValue = userCurrentTimeTo?.timeMinutes

        switch (fromValue, toValue) {
        case (nil, nil):
            return true
        case let (.some(fromMinutes), .some(toMinutes)):
            let now = Date()
            let components = Calendar.current.dateComponents([.hour, .minute], from: now)
            let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

            if fromMinutes == toMinutes {
                return true
            }

            if fromMinutes < toMinutes {
                return currentMinutes >= fromMinutes && currentMinutes <= toMinutes
            }

            return currentMinutes >= fromMinutes || currentMinutes <= toMinutes
        default:
            return false
        }
    }
}
