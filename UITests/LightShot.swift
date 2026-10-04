import XCTest
/// Light mode pairs the CHROME with the light terminal (one switch):
/// terminal, ⋯ menu, and the session list all on light paper.
final class LightShot: XCTestCase {
    private func shoot(_ path: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
    func testLightModePairsChrome() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        // -termLight YES: the argument domain sets the same UserDefaults key
        // the @AppStorage switch reads.
        app.launchArguments += ["-hop-ui-testing", "-termLight", "YES"]
        app.launchEnvironment["HOP_DEV_OPEN"] = "room"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        sleep(2)
        shoot("/tmp/hop-light-terminal.png")
        app.buttons["hide keyboard"].firstMatch.tap()
        sleep(1)
        app.buttons["Terminal actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5), "menu did not open")
        sleep(1)
        shoot("/tmp/hop-light-menu.png")
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Display"].waitForExistence(timeout: 4))
        app.buttons["Display"].firstMatch.tap()
        // The toggle names the OTHER mode — while light, it offers Dark.
        XCTAssertTrue(app.buttons["Dark mode"].waitForExistence(timeout: 4),
                      "Display should offer 'Dark mode' while in light mode")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        sleep(1)
        app.buttons["Back to sessions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Terminal actions"].waitForNonExistence(timeout: 5))
        sleep(2)
        shoot("/tmp/hop-light-list.png")
    }
}
