#if !SWIFT_PACKAGE
import Foundation

private final class SDKResourceBundleToken {}

extension Bundle {
    static let module: Bundle = {
        let moduleBundle = Bundle(for: SDKResourceBundleToken.self)
        for container in [moduleBundle, Bundle.main] {
            if let url = container.url(forResource: "SimlaTracker", withExtension: "bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        fatalError("Missing SimlaTracker.bundle")
    }()
}
#endif
