import XCTest
/// Each briefing story is its own row: swipe left clears THAT story only.
final class BriefingSwipe: XCTestCase {
    func testSwipeClearsOneStoryAtATime() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let stamp = "2026-10-04T\(Int(Date().timeIntervalSince1970) % 86400 / 3600 + 10):00:00.000Z"
        let digest: [String: Any] = [
            "generated_at": stamp, "summary": "Three stories.",
            "items": [
                ["session": "probe-a", "slot": "watch", "urgency": "blocked", "headline": "Story Alpha stalls", "why": "A."],
                ["session": "probe-b", "slot": "watch", "urgency": "blocked", "headline": "Story Bravo waits", "why": "B."],
                ["session": "probe-c", "slot": "done", "urgency": "finished", "headline": "Story Charlie lands", "why": "C."]
            ]
        ]
        let path = "/tmp/hop-dev-digest-swipe.json"
        try JSONSerialization.data(withJSONObject: digest).write(to: URL(fileURLWithPath: path))
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_DIGEST"] = path
        app.launch()
        let bravo = app.staticTexts["Story Bravo waits"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 20), "briefing never rendered")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-brief-before.png"))
        bravo.swipeLeft()
        let clear = app.buttons["Clear"]
        if clear.waitForExistence(timeout: 3) { clear.tap() }
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: bravo, handler: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Story Alpha stalls"].exists, "clearing one story took another")
        XCTAssertTrue(app.staticTexts["Story Charlie lands"].exists, "clearing one story took another")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-brief-after.png"))
        // The list still scrolls (a swipe-row must not eat vertical drags).
        let alpha = app.staticTexts["Story Alpha stalls"]
        let y0 = alpha.frame.minY
        app.swipeUp()
        sleep(1)
        XCTAssertTrue(!alpha.exists || alpha.frame.minY < y0 - 50, "the list did not scroll")
    }
}
