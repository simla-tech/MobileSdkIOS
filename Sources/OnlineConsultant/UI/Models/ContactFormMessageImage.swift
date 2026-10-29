import Foundation

/// Image resolved for a contact-form message.
package struct ContactFormMessageImage: Equatable {

    /// Local, remote, data, or file URL used to render the image.
    package let url: URL

    /// Optional source image size used to keep the rendered image aspect ratio.
    package let size: CGSize?

    package init(url: URL, size: CGSize?) {
        self.url = url
        self.size = size
    }
}
