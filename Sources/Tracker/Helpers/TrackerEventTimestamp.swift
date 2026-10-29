//
//  TrackerEventTimestamp.swift
//  ConsultantSdk
//
//  Created by Yriy Deviataev on 10.09.2026.
//

import Foundation

package enum TrackerEventTimestamp {
    package static func make(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.string(from: date)
    }
}
