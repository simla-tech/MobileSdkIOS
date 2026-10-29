//
//  OnlineConsultantCachePolicy.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

import Foundation

/// Defines how the SDK stores and cleans up cached remote files on disk.
public struct OnlineConsultantCachePolicy: Equatable, Sendable {

    /// The maximum total size, in bytes, allowed for cached files.
    ///
    /// When the value is `nil`, the SDK does not limit the cache by disk size.
    public let maxDiskSizeBytes: Int64?

    /// The maximum age, in seconds, allowed for cached files.
    ///
    /// When the value is `nil`, the SDK does not remove cached files by age.
    public let maxFileAge: TimeInterval?

    /// A Boolean value that determines whether the SDK applies this cleanup policy automatically.
    ///
    /// When set to `true`, the SDK calls cache trimming after storing or downloading cached files.
    /// Trimming removes missing cache entries and then applies `maxFileAge` and `maxDiskSizeBytes`.
    /// When set to `false`, cached files are kept until `trimCache()` or `clearCache()` is called.
    public let automaticCleanup: Bool

    /// Creates a cache policy for files stored by the SDK.
    ///
    /// - Parameters:
    ///   - maxDiskSizeBytes: The maximum total size, in bytes, allowed for cached files.
    ///     Pass `nil` to disable size-based cleanup.
    ///   - maxFileAge: The maximum age, in seconds, allowed for cached files.
    ///     Pass `nil` to disable age-based cleanup.
    ///   - automaticCleanup: Whether the SDK should apply this cleanup policy automatically after
    ///     storing or downloading cached files. Pass `false` to manage cache cleanup manually.
    public init(
        maxDiskSizeBytes: Int64? = nil,
        maxFileAge: TimeInterval? = nil,
        automaticCleanup: Bool = true
    ) {
        self.maxDiskSizeBytes = maxDiskSizeBytes
        self.maxFileAge = maxFileAge
        self.automaticCleanup = automaticCleanup
    }
}
