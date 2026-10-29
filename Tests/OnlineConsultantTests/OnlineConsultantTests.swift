import XCTest
@testable import Core
@testable import OnlineConsultant

@MainActor
final class OnlineConsultantTests: XCTestCase {

    func testControllerPublishesInitialState() {
        let controller = OnlineConsultantController(
            config: OnlineConsultantConfig(),
            sessionRuntime: SessionRuntime(config: SessionConfig(siteToken: "site-token"))
        )
        var observedState: ControllerState?
        var observedUnread: Int?

        controller.onStateChange = { observedState = $0 }
        controller.onUnreadIncomingMessagesCountChange = { observedUnread = $0 }

        XCTAssertEqual(observedState, .idle)
        XCTAssertEqual(observedUnread, 0)
        XCTAssertEqual(controller.unreadIncomingMessagesCount, 0)
        let observer = OnlineConsultantObserver(onlineConsultant: controller)
        XCTAssertEqual(observer.unreadIncomingMessagesCount, 0)
        var observerCount: Int?
        observer.onUnreadIncomingMessagesCountChange = { observerCount = $0 }
        XCTAssertEqual(observerCount, 0)
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertEqual(controller.linkSettings, LinkSettings())
    }
}
