import XCTest
/// Open Views and an HTML result, and shoot what the reader shows over time —
/// "I still have trouble opening html in hop view" (2026-11-01).
final class HtmlViewProbe: XCTestCase {
    func testOpenHtmlView() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let out = ProcessInfo.processInfo.environment["HOP_ROTATE_OUT"] ?? NSTemporaryDirectory()
        let title = ProcessInfo.processInfo.environment["HOP_PROBE_TITLE"] ?? "V2 model architecture"
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchEnvironment["HOP_DEV_SHEET"] = "views"
        app.launch()
        sleep(6)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let c = springboard.descendants(matching: .button).matching(identifier: "Cancel").firstMatch
            guard c.exists else { break }
            c.tap(); sleep(1)
        }
        func shot(_ n: String) {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out + "/html-\(n).png"))
        }
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        for t in [1, 3, 8, 15] {
            sleep(t == 1 ? 1 : UInt32(t - [1, 3, 8, 15][max(0, [1, 3, 8, 15].firstIndex(of: t)! - 1)]))
            shot("\(t)s")
        }
        try? app.debugDescription.write(toFile: out + "/html-tree.txt", atomically: true, encoding: .utf8)
        // Interact: scroll the page, then tap in it.
        app.webViews.firstMatch.swipeUp(); sleep(1); shot("scrolled")
        // A sideways drag on wide content should pan the PAGE, not page to
        // the next result.
        app.webViews.firstMatch.swipeLeft(); sleep(2); shot("swiped-left")
        app.webViews.firstMatch.tap(); sleep(1); shot("tapped")
    }
}
