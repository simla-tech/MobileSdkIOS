/// Response returned after uploading a file to the consultant backend.
///
/// The backend returns only the uploaded Transport file identifier. A download URL is resolved
/// separately through the file link endpoint.
 package struct ConsultantFileUploadResponse: Decodable, Equatable, Sendable {

    /// Uploaded file identifier used later as `items[].id` when sending file or image messages.
     package let id: FlexibleID?

    package init(id: FlexibleID?) {
        self.id = id
    }
}
