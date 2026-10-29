import UIKit

/// Tracks foreground availability across application and scene lifecycle notifications.
@MainActor
package final class ConsultantApplicationLifecycle: NSObject {
    package private(set) var isInForeground: Bool
    package var onForegroundChange: ((Bool) -> Void)?

    private let notificationCenter: NotificationCenter
    private var foregroundSceneIDs: Set<String>
    private let sceneIdentifier: @MainActor (Any?) -> String?

    package init(
        notificationCenter: NotificationCenter = .default,
        initiallyInForeground: Bool? = nil,
        initialForegroundSceneIDs: Set<String>? = nil,
        sceneIdentifier: @escaping @MainActor (Any?) -> String? = { ($0 as? UIScene)?.session.persistentIdentifier }
    ) {
        let scenes = UIApplication.shared.connectedScenes
        let foregroundScenes = Set(scenes.filter {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }.map { $0.session.persistentIdentifier })
        self.notificationCenter = notificationCenter
        self.foregroundSceneIDs = initialForegroundSceneIDs ?? foregroundScenes
        self.isInForeground = initiallyInForeground ?? (scenes.isEmpty
            ? UIApplication.shared.applicationState != .background
            : !foregroundScenes.isEmpty)
        self.sceneIdentifier = sceneIdentifier
        super.init()

        notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(sceneWillEnterForeground), name: UIScene.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(sceneWillEnterForeground), name: UIScene.didActivateNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(sceneDidLeaveForeground), name: UIScene.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(sceneDidLeaveForeground), name: UIScene.didDisconnectNotification, object: nil)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc private func applicationWillEnterForeground() {
        setForeground(true)
    }

    @objc private func applicationDidEnterBackground() {
        foregroundSceneIDs.removeAll()
        setForeground(false)
    }

    @objc private func sceneWillEnterForeground(_ notification: Notification) {
        guard let id = sceneIdentifier(notification.object) else { return }
        foregroundSceneIDs.insert(id)
        setForeground(true)
    }

    @objc private func sceneDidLeaveForeground(_ notification: Notification) {
        guard let id = sceneIdentifier(notification.object) else { return }
        foregroundSceneIDs.remove(id)
        setForeground(!foregroundSceneIDs.isEmpty)
    }

    private func setForeground(_ value: Bool) {
        guard isInForeground != value else { return }
        isInForeground = value
        onForegroundChange?(value)
    }
}
