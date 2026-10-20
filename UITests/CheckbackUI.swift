import XCTest
/// Check-backs on the phone: schedule from the ⋯ menu, see it waiting, cancel.
final class CheckbackUI: XCTestCase {
    private func post(_ path: String, _ body: [String: Any], _ cookie: String) -> Bool {
        var req = URLRequest(url: URL(string: "https://hop.zhoulab.io/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, r, _ in ok = (r as? HTTPURLResponse)?.statusCode == 200; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return ok
    }
    func testScheduleAndCancelFromTheMenu() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "CheckbackProbe"
        _ = post("api/sessions/delete", ["name": scratch], cookie)
        sleep(1)
        XCTAssertTrue(post("api/sessions", ["name": scratch, "type": "terminal"], cookie))
        defer { _ = post("api/sessions/delete", ["name": scratch], cookie) }
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["Terminal actions"].tap()
        let item = app.buttons["Check back later…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu has no check-back item")
        item.tap()
        let field = app.textFields["checkback message"].exists ? app.textFields["checkback message"] : app.textViews["checkback message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "sheet did not open")
        field.tap()
        field.typeText("echo cb-probe-77")
        app.buttons["schedule checkback"].tap()
        let waiting = app.staticTexts["echo cb-probe-77"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "scheduled check-back not listed")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-checkback.png"))
        // Cancel it with a swipe.
        waiting.swipeLeft()
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        let cancelled = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'cancelled'")).firstMatch
        XCTAssertTrue(cancelled.waitForExistence(timeout: 10), "cancel did not move it to Recent")
    }
}
