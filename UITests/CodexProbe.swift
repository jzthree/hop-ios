import XCTest
/// Codex in a scratch session the simulator alone sizes: long-press selects
/// and offers the native menu; a tap in the composer walks the caret there
/// with arrows (Codex has no mouse mode). Screens photographed for review.
final class CodexProbe: XCTestCase {
    private func daemonPOST(_ path: String, _ body: [String: Any], cookie: String) -> Bool {
        guard let url = URL(string: "https://hop.zhoulab.io/\(path)") else { return false }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var ok = false; let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in ok = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 10); return ok
    }
    private func shoot(_ p: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: p)) }
    func testCodexSelectAndTapToMove() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "CodexProbe"
        _ = daemonPOST("api/sessions/delete", ["name": scratch, "internalName": scratch], cookie: cookie)
        sleep(1)
        XCTAssertTrue(daemonPOST("api/sessions", ["name": scratch, "type": "terminal"], cookie: cookie))
        defer { _ = daemonPOST("api/sessions/delete", ["name": scratch, "internalName": scratch], cookie: cookie) }
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_SELECT_MARKER"] = "/tmp/hop-codex-select-trace.txt"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8))
        sleep(1)
        app.typeText("codex\n")
        sleep(10)
        shoot("/tmp/hop-codex-1-started.png")
        // Something to select and to walk in: composer text, never submitted.
        app.typeText("hello world tap test")
        sleep(2)
        shoot("/tmp/hop-codex-2-typed.png")
        let byLabel = { (l: String) in app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", l)).firstMatch }
        // Long-press on transcript text, clear of the top chrome-summon zone.
        for (i, spot) in [CGVector(dx: 0.25, dy: 0.25), CGVector(dx: 0.2, dy: 0.55)].enumerated() {
            app.coordinate(withNormalizedOffset: spot).press(forDuration: 0.7)
            sleep(2)
            shoot("/tmp/hop-codex-3-select-\(i).png")
            print("PROBE hold\(i) copy=\(byLabel("Copy").exists) paste=\(byLabel("Paste").exists)")
            if byLabel("Copy").exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap(); sleep(1) }
        }
        // Tap near the start of the composer text: the caret should walk left.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.55)).tap()
        sleep(2)
        shoot("/tmp/hop-codex-4-tapped.png")
        // Quit codex without submitting anything, then leave the shell.
        app.typeText("\u{3}"); sleep(1); app.typeText("\u{3}"); sleep(2)
        shoot("/tmp/hop-codex-5-quit.png")
        app.typeText("exit\n")
    }
}
