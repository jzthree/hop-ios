import XCTest
final class MenuShot: XCTestCase {
    func testOpenActionsMenuAndShoot() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = "room"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].firstMatch.tap()
        sleep(1)
        let menu = app.buttons["Terminal actions"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["Find"].waitForExistence(timeout: 5), "menu did not open")
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-menu.png"))
        // Every top-level row and the new verbs must be present.
        // Every top-level row is on screen at once — the whole point of the
        // regroup (Display/Sharing/Session fold under More).
        for label in ["Views", "Notify when", "Find", "Copy", "Open link…", "Add photo",
                      "Hand off", "Display", "Sharing", "Session"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            XCTAssertTrue(row.exists, "missing menu row: \(label)")
            XCTAssertTrue(row.isHittable, "menu row below the fold: \(label)")
        }
        // No junk drawer: "More" named nothing and buried text size three
        // levels deep. Every group is now self-describing at the top level.
        XCTAssertFalse(app.buttons["More"].exists, "the junk-drawer row came back")
        // The three handoff verbs are one intent, so they share one row.
        // The daemon reports `zsh` as a claude session's foreground process,
        // so the client can't know the tool and offers BOTH handoffs; the
        // daemon refuses a same-tool one with its error.
        app.buttons["Hand off"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fork session"].waitForExistence(timeout: 4), "Fork missing under Hand off")
        XCTAssertTrue(app.buttons["Continue in Codex…"].exists, "Codex handoff missing")
        XCTAssertTrue(app.buttons["Continue in Claude…"].exists, "Claude handoff missing")
        app.buttons["Hand off"].firstMatch.tap()      // back out
        // Text size is now TWO taps, not three.
        XCTAssertTrue(app.buttons["Display"].waitForExistence(timeout: 4), "Display missing at top level")
        app.buttons["Display"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Bigger text"].waitForExistence(timeout: 4), "Display submenu missing Bigger text")
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-menu-display.png"))
    }
}
