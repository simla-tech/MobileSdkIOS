//
//  ConsultantActionExecuteResponse.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Response returned after an automatic site action is marked as executed.
///
/// The backend response currently contains only `execution_id`, which is later used when the user
/// closes the action, submits an action contact form, or replies to an automatic message.
 package struct ConsultantActionExecuteResponse: Decodable, Equatable, Sendable {

    /// Identifier of the created action execution record.
     package let executionID: FlexibleID?

    private enum CodingKeys: String, CodingKey {
        case executionID = "execution_id"
    }

    package init(executionID: FlexibleID?) {
        self.executionID = executionID
    }
}
