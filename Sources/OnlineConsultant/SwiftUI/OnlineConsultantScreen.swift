import SwiftUI

/// SwiftUI view that embeds the SDK's shared chat view controller.
@MainActor
public struct OnlineConsultantScreen: UIViewControllerRepresentable {

    /// Creates a chat screen backed by `Consultant.shared.onlineConsultant`.
    public init() {}

    /// Creates the UIKit consultant chat screen for SwiftUI.
    ///
    /// - Parameters:
    ///   - context: SwiftUI context for the UIKit chat screen.
    public func makeUIViewController(context: Context) -> OnlineConsultantViewController {
        OnlineConsultantViewController()
    }

    /// Retains the shared UIKit chat screen when SwiftUI refreshes the wrapper.
    ///
    /// - Parameters:
    ///   - uiViewController: UIKit chat screen managed by SwiftUI.
    ///   - context: SwiftUI context for the UIKit chat screen.
    public func updateUIViewController(
        _ uiViewController: OnlineConsultantViewController,
        context: Context
    ) {}
}
