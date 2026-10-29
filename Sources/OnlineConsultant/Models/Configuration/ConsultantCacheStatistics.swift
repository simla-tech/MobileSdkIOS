//
//  ConsultantCacheStatistics.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 15.07.2026.
//

/// Local SDK file cache statistics.
///
/// This model is not decoded from the consultant backend. It describes the current on-device cache
/// state returned by `cacheStatistics()` and `trimCache()`.
public struct ConsultantCacheStatistics: Equatable, Sendable {

    /// Number of cached file entries currently tracked by the cache manifest.
    public let fileCount: Int

    /// Total disk size of cached files in bytes.
    public let totalDiskSizeBytes: Int64

    /// Creates a file cache statistics snapshot.
    ///
    /// - Parameters:
    ///   - fileCount: Number of files currently present in the local chat cache.
    ///   - totalDiskSizeBytes: Total size of local cached files in bytes.
    public init(
        fileCount: Int,
        totalDiskSizeBytes: Int64
    ) {
        self.fileCount = fileCount
        self.totalDiskSizeBytes = totalDiskSizeBytes
    }
}
