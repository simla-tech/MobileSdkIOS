import XCTest
@testable import Core
@testable import OnlineConsultant

final class ConsultantConfigTests: XCTestCase {

    func testDefaultConfigValues() {
        let config = CrmSdkConfig(siteToken: "site-token")

        XCTAssertEqual(config.consultantConfig.connectTimeout, 30)
        XCTAssertEqual(config.requestTimeout, 30)
        XCTAssertEqual(config.resourceTimeout, 60)
        XCTAssertEqual(config.consultantConfig.initialMessagesLimit, 50)
        XCTAssertEqual(config.consultantConfig.cachePolicy, OnlineConsultantCachePolicy())
    }

    func testLinkSettingsReflectDecodedConfiguration() throws {
        let data = Data("""
        {
            "links": [{"type": "telegram", "url": "retailcrm"}],
            "links_mode": "widget",
            "links_orientation": "horizontal",
            "always_show_links_on_desktops": true
        }
        """.utf8)
        let config = try JSONDecoder().decode(ConsultantConfig.self, from: data)

        XCTAssertEqual(
            config.linkSettings,
            LinkSettings(
                links: [ConsultantLink(type: .telegram, url: "retailcrm")],
                linksMode: .widget,
                linksOrientation: .horizontal,
                alwaysShowLinksOnDesktops: true
            )
        )
    }
}
