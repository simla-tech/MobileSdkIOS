//
//  URL.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 22.07.2026.
//

import Foundation
import UniformTypeIdentifiers

package extension URL {

    var fileName: String {
        let fileName = lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? "file-\(UUID().uuidString)" : fileName
    }

    var contentType: String {
        if let contentType = try? resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.preferredMIMEType ?? "application/octet-stream"
        }

        if let contentType = UTType(filenameExtension: pathExtension) {
            return contentType.preferredMIMEType ?? "application/octet-stream"
        }

        return "application/octet-stream"
    }

    func fileSize() throws -> Int? {
        let values = try resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize
    }
}
