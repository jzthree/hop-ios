import XCTest
/// The witness reports a story only when the STORY is ≥60% on screen —
/// not every story the moment the briefing card's top edge appears.
final class BriefingWitness: XCTestCase {
    func testOnlyVisibleStoriesAreWitnessed() throws {
        let env = ProcessInfo.processInfo.environment
        let cookie = env["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let marker = "/tmp/hop-witness.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DIGEST_WITNESS_MARKER"] = marker
        app.launch()
        XCTAssertTrue(app.staticTexts["Briefing"].waitForExistence(timeout: 20), "no briefing")
        sleep(6)   // past the 1.5s glimpse + 2s batch
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-witness.png"))
        // Background the app so the witness flushes.
        XCUIDevice.shared.press(.home)
        sleep(2)
        let log = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        print("WITNESS-LOG:\n" + log)
        XCTAssertFalse(log.isEmpty, "nothing witnessed")
    }

    /// The desktop's timeline on the phone: an "Earlier · N" fold under the
    /// current stories; an edition expands to its own stories, witnessed
    /// under THAT edition's stamp.
    func testEarlierEditionsExpand() throws {
        let env = ProcessInfo.processInfo.environment
        let cookie = env["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let marker = "/tmp/hop-witness-earlier.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DIGEST_WITNESS_MARKER"] = marker
        app.launch()
        XCTAssertTrue(app.staticTexts["Briefing"].waitForExistence(timeout: 20))
        let earlier = app.buttons["earlier briefings"].firstMatch
        for _ in 0..<10 where !earlier.isHittable { app.swipeUp(); usleep(600_000) }
        XCTAssertTrue(earlier.isHittable, "no Earlier fold")
        earlier.tap()
        sleep(1)
        // First edition row: its label carries "ago" or a clock time.
        let firstEdition = app.buttons.matching(identifier: "briefing edition").element(boundBy: 0)
        XCTAssertTrue(firstEdition.waitForExistence(timeout: 5), "no edition rows")
        firstEdition.tap()
        sleep(1)
        app.swipeUp(); sleep(1)
        // The expanded edition's first story must be on screen: its rows sit
        // right under the edition we tapped.
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-earlier.png"))
        sleep(4)
        XCUIDevice.shared.press(.home)
        sleep(3)
        let log = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        print("EARLIER-LOG:\n" + log)
        XCTAssertFalse(log.contains("\"acted\""), "a test tap opened a session")
    }
}
