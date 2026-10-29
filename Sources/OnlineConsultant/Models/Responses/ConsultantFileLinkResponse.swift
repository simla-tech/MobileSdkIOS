//
//  ConsultantFileLinkResponse.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 20.07.2026.
//

/// Backend response for `GET /api/client/v1/files/:file_id`.
///
/// The backend returns the requested file identifier and a temporary file URL. The SDK decodes only
/// the URL because the file identifier is already known from the request and is not used after the
/// link is resolved.
package struct ConsultantFileLinkResponse: Decodable, Equatable {

    /// Temporary URL that can be used to download or preview the requested file.
    package let url: String?

    package init(url: String?) {
        self.url = url
    }
}
