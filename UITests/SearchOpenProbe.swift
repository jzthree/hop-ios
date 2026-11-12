import XCTest

/// Search, then open a match while the keyboard is still up, then go
/// back — the path build 406 crashed on (iOS 27.2, 2026-11-11: the terminal
/// took the keyboard in the middle of the push, UIKit trapped in layout).
final class SearchOpenProbe: XCTestCase {
    func testOpenMatchWithKeyboardUp() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let query = ProcessInfo.processInfo.environment["HOP_SEARCH_QUERY"] ?? "hop"
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        let field = app.textFields["Search sessions by name"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), "never reached the session list")
        for round in 0..<3 {
            field.tap()
            field.typeText(query)
            sleep(2)
            let cell = app.cells.firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 8))
            cell.tap()
            sleep(3)
            XCTAssertEqual(app.state, .runningForeground, "crashed opening a match, round \(round)")
            // The terminal still takes the keyboard — after the push, not in it.
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4), "no keyboard in the terminal, round \(round)")
            if round == 0 {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
            }
            // Back by the button: a left-edge swipe in a terminal opens the drawer.
            if !field.waitForExistence(timeout: 2) {
                app.buttons["Back to sessions"].firstMatch.tap()
            }
            XCTAssertTrue(field.waitForExistence(timeout: 6), "not back on the list, round \(round)")
            XCTAssertEqual(app.state, .runningForeground, "crashed going back, round \(round)")
            if field.exists, let v = field.value as? String, !v.isEmpty, v != "Search sessions by name" {
                app.buttons["Clear search"].firstMatch.tap()
            }
        }
    }
}
