import UIKit
import XCTest
@testable import OnlineConsultant

@MainActor
final class ConsultantApplicationLifecycleTests: XCTestCase {
    func testKeepsConnectionAvailableUntilLastForegroundSceneLeaves() {
        let center = NotificationCenter()
        let lifecycle = ConsultantApplicationLifecycle(
            notificationCenter: center, initiallyInForeground: true,
            initialForegroundSceneIDs: ["first", "second"],
            sceneIdentifier: { $0 as? String }
        )
        var changes: [Bool] = []
        lifecycle.onForegroundChange = { changes.append($0) }

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIScene.willDeactivateNotification, object: "first")
        center.post(name: UIScene.didEnterBackgroundNotification, object: "first")
        XCTAssertTrue(lifecycle.isInForeground)
        XCTAssertTrue(changes.isEmpty)

        center.post(name: UIScene.didDisconnectNotification, object: "second")
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(changes, [false])

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        center.post(name: UIScene.willEnterForegroundNotification, object: "first")
        center.post(name: UIScene.willEnterForegroundNotification, object: "first")
        XCTAssertTrue(lifecycle.isInForeground)
        XCTAssertEqual(changes, [false, true])
    }

    func testSupportsApplicationLifecycleWithoutScenes() {
        let center = NotificationCenter()
        let lifecycle = ConsultantApplicationLifecycle(
            notificationCenter: center, initiallyInForeground: false, initialForegroundSceneIDs: []
        )
        var changes: [Bool] = []
        lifecycle.onForegroundChange = { changes.append($0) }
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(lifecycle.isInForeground)
        XCTAssertEqual(changes, [true, false])
    }

    func testActivationRecoversWhenCreatedDuringForegroundTransition() {
        let center = NotificationCenter()
        let lifecycle = ConsultantApplicationLifecycle(
            notificationCenter: center, initiallyInForeground: false,
            initialForegroundSceneIDs: [], sceneIdentifier: { $0 as? String }
        )
        var changes: [Bool] = []
        lifecycle.onForegroundChange = { changes.append($0) }
        center.post(name: UIScene.didActivateNotification, object: "first")
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(lifecycle.isInForeground)
        XCTAssertEqual(changes, [true])
        center.post(name: UIScene.didEnterBackgroundNotification, object: "first")
        XCTAssertEqual(changes, [true, false])
    }
}
