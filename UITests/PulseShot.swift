import XCTest
final class PulseShot: XCTestCase {
    func testPulseCardOnTheWall() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        XCTAssertTrue(app.staticTexts["Briefing"].waitForExistence(timeout: 20))
        let pulse = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'may be overlooked'")).firstMatch
        for _ in 0..<8 where !(pulse.exists && pulse.isHittable) { app.swipeUp(); usleep(500_000) }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-pulse.png"))
        XCTAssertTrue(pulse.exists, "no pulse card")
    }
}
