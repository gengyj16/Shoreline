import XCTest

final class ShorelineUITests: XCTestCase {
    private let suite = "local.shoreline.wallpaper.tests.\(UUID().uuidString)"
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { UserDefaults.standard.removePersistentDomain(forName: suite) }

    @MainActor func testSettingsThemeSwitchAndPlayback() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment = ["SHORELINE_UI_TESTING": "1", "SHORELINE_TEST_SUITE": suite]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["岸屿 Shoreline"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let meadow = window.buttons["theme-meadow"]
        let beach = window.buttons["theme-beach"]
        meadow.click()
        XCTAssertTrue(window.staticTexts["草地设置"].waitForExistence(timeout: 5))
        window.buttons["暂停动画"].click()
        XCTAssertTrue(window.buttons["继续动画"].exists)
        window.buttons["继续动画"].click()
        beach.click()
        XCTAssertTrue(window.staticTexts["沙滩设置"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Native settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testFinderConnectionIsVisible() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment = ["SHORELINE_UI_TESTING": "1", "SHORELINE_TEST_SUITE": suite]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["岸屿 Shoreline"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        if window.buttons["打开授权设置"].exists {
            throw XCTSkip("Enable Shoreline in System Settings > Privacy & Security > Accessibility to run the Finder integration test.")
        }
        let connected = window.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "已连接 Finder", "已连接 Finder")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 10), window.debugDescription)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Finder connection"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
