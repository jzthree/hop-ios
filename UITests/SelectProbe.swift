import XCTest
/// Long-press selection in a REAL Claude session (the fixture), both with
/// the keyboard down and up — the passing select test only covers a quiet
/// scratch shell with the keyboard up.
final class SelectProbe: XCTestCase {
    private func launch(_ marker: String) -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = env["HOP_E2E_FIXTURE"] ?? "nebula"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_SELECT_MARKER"] = marker
        try? FileManager.default.removeItem(atPath: marker)
        app.launch()
        return app
    }
    private func copyShown(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy"))
            .firstMatch.waitForExistence(timeout: 5)
    }
    func testHoldSelectsInClaudeKeyboardDown() throws {
        let m = "/tmp/hop-probe-kbdown.txt"
        let app = launch(m)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].firstMatch.tap()
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).press(forDuration: 0.8)
        let ok = copyShown(app)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-probe-kbdown.png"))
        print("PROBE-TRACE kbdown:\n" + ((try? String(contentsOfFile: m, encoding: .utf8)) ?? "<none>"))
        XCTAssertTrue(ok, "no Copy menu after a hold (keyboard down)")
    }
    func testHoldSelectsInClaudeKeyboardUp() throws {
        let m = "/tmp/hop-probe-kbup.txt"
        let app = launch(m)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 0.8)
        let ok = copyShown(app)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-probe-kbup.png"))
        print("PROBE-TRACE kbup:\n" + ((try? String(contentsOfFile: m, encoding: .utf8)) ?? "<none>"))
        XCTAssertTrue(ok, "no Copy menu after a hold (keyboard up)")
    }

    /// A REAL finger drifts while it settles. The device trace (2026-09-28)
    /// showed the scroll pan claiming ~10pt of drift ~30ms after touch-down
    /// and failing every hold. Press, slide 12pt slowly, then hold: must
    /// still select.
    func testHoldSurvivesFingertipDrift() throws {
        let m = "/tmp/hop-probe-drift.txt"
        let app = launch(m)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].firstMatch.tap()
        sleep(2)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        let to = from.withOffset(CGVector(dx: 6, dy: 10))   // ~12pt
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 60, thenHoldForDuration: 0.9)
        let ok = copyShown(app)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-probe-drift.png"))
        print("PROBE-TRACE drift:\n" + ((try? String(contentsOfFile: m, encoding: .utf8)) ?? "<none>"))
        XCTAssertTrue(ok, "a drifting hold did not select")
    }

    private func post(_ path: String, _ body: [String: Any], _ cookie: String) -> Bool {
        var req = URLRequest(url: URL(string: "https://hop.zhoulab.io/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, r, _ in
            ok = (r as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return ok
    }
    /// The dead zone must not cost scrolling: a drag on a shell with real
    /// scrollback still moves the viewport (the Live button is the witness).
    func testDragStillScrollsWithSlop() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "SlopScrollProbe"
        _ = post("api/sessions/delete", ["name": scratch, "internalName": scratch], cookie)
        sleep(1)
        XCTAssertTrue(post("api/sessions", ["name": scratch, "type": "terminal"], cookie))
        defer { _ = post("api/sessions/delete", ["name": scratch, "internalName": scratch], cookie) }
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8))
        app.typeText("seq 1 400\n")
        sleep(2)
        app.buttons["hide keyboard"].firstMatch.tap()
        sleep(1)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        top.press(forDuration: 0.05, thenDragTo: low)
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout: 5), "drag did not scroll")
    }
}
