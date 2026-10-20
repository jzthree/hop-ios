import XCTest
/// A new `hop view` delivery floats in a corner: draggable, closable, tap opens.
final class FloatPreview: XCTestCase {
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
    func testNewDeliveryFloatsMovesAndOpens() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "FloatProbe"
        _ = post("api/sessions/delete", ["name": scratch], cookie)
        sleep(1)
        XCTAssertTrue(post("api/sessions", ["name": scratch, "type": "terminal"], cookie))
        defer { _ = post("api/sessions/delete", ["name": scratch], cookie) }
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_KBLOG_MARKER"] = "/tmp/hop-kb.txt"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        sleep(1)
        // The agent hands over TWO results, from inside the session.
        app.typeText("~/Code/hop2/hop view /tmp/hop-float-a.md --title 'Float A'; sleep 1; ~/Code/hop2/hop view /tmp/hop-float-b.html --title 'Float B'\n")
        let card = app.otherElements["floating preview"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "new deliveries never floated")
        let open = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Open Float'")).firstMatch
        expectation(for: NSPredicate(format: "value == '1/2 · 2 unread'"), evaluatedWith: open, handler: nil)
        waitForExpectations(timeout: 20)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-float-1.png"))
        // Swipe WITHIN the card: page 2.
        let f = open.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX + 50, dy: f.minY + 40))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX - 60, dy: f.minY + 42)))
        sleep(1)
        XCTAssertTrue((open.value as? String ?? "").hasPrefix("2/2"), "swipe inside the card did not page: \(open.value ?? "")")
        XCTAssertLessThan(abs(open.frame.midX - f.midX), 20, "paging swipe moved the card")
        // Tap opens the viewer; coming back, the card is STILL there, one fewer unread.
        open.tap()
        XCTAssertTrue(app.buttons["Hide controls"].waitForExistence(timeout: 10), "tap did not open the viewer")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8), "card did not come back after the viewer")
        let reopened = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Open Float'")).firstMatch
        expectation(for: NSPredicate(format: "value ENDSWITH '1 unread'"), evaluatedWith: reopened, handler: nil)
        waitForExpectations(timeout: 8)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-float-2.png"))
        // Dragging the title bar MOVES the card (paging is for the picture).
        let r = reopened.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: r.midX, dy: r.maxY - 10))
            // toward the OPPOSITE corner of wherever it rests (the corner persists)
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(
                dx: r.midX < app.frame.midX ? 0.85 : 0.15, dy: r.midY < app.frame.midY ? 0.6 : 0.2)))
        sleep(1)
        let moved = hypot(reopened.frame.midX - r.midX, reopened.frame.midY - r.midY)
        XCTAssertGreaterThan(moved, 120, "dragging the bar did not move the card (moved \(Int(moved))pt)")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-float-3.png"))
        // Dragging ON THE PAGE (vertically) moves the card too — the web
        // view underneath must not take that drag as a scroll.
        let r2 = reopened.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: r2.midX - 30, dy: r2.minY + 50))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(
                dx: r2.midX < app.frame.midX ? 0.25 : 0.75, dy: r2.midY < app.frame.midY ? 0.65 : 0.2)))
        sleep(1)
        let moved2 = hypot(reopened.frame.midX - r2.midX, reopened.frame.midY - r2.midY)
        XCTAssertGreaterThan(moved2, 120, "dragging the page did not move the card (moved \(Int(moved2))pt)")
        // Only the ✕ puts it away.
        app.buttons["Close preview"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: card, handler: nil)
        waitForExpectations(timeout: 5)
    }
}
