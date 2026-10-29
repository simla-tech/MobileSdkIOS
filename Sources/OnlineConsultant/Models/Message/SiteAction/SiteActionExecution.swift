//
//  SiteActionExecution.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Last execution state for a retryable site action.
///
/// The backend includes this object in `last_execution` only for actions that allow retry. Frontend
/// uses it to decide whether and when the action can be shown again.
package struct SiteActionExecution: Decodable, Equatable, Sendable {

    /// Identifier of the last action execution record.
    package let id: FlexibleID?

    /// Result assigned to the last execution, for example `close_consultant`, `go_to_page`, or `answer`.
    package let result: String?

    /// Number of seconds since `result` was assigned on the backend.
    private let secSinceResult: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case secSinceResult = "sec_since_result"
    }

    package init(
        id: FlexibleID?,
        result: String?,
        secSinceResult: Int?
    ) {
        self.id = id
        self.result = result
        self.secSinceResult = secSinceResult
    }
}
