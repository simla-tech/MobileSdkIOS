import XCTest
@testable import OnlineConsultant

final class ProductImagePreviewURLTests: XCTestCase {
    func testDirectSignedURLPreservesExistingPercentEscapes() {
        let source = "https://files.example.com/photo%20one.png?signature=a%2Fb%3D"
        XCTAssertEqual(ProductImagePreviewURL.make(imageURLString: source, imageWorkers: [])?.absoluteString, source)
    }

    func testWorkerURLPreservesSignedSourceWithoutDoubleEncoding() {
        let source = "https://files.example.com/photo%20one.png?signature=a%2Fb%3D"
        XCTAssertEqual(
            ProductImagePreviewURL.make(imageURLString: source, imageWorkers: ["images.example.com"], resize: "304x-")?.absoluteString,
            "https://images.example.com/r/304x-/" + source
        )
    }

    func testUnescapedSpacesAreEncodedOnceAndProtocolRelativeURLsAreNormalized() {
        XCTAssertEqual(
            ProductImagePreviewURL.make(imageURLString: " //files.example.com/photo one.png ", imageWorkers: [])?.absoluteString,
            "https://files.example.com/photo%20one.png"
        )
    }
}
