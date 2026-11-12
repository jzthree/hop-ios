import XCTest

/// Background → foreground with the keyboard up, on an alt-screen session —
/// "incorrect session size after returning from another app" (2026-11-11
/// diagnostic: the terminal came back 183pt above where SwiftUI put it).
/// Needs a session (HOP_PROBE_SESSION) running a full-screen app.
final class WakeShiftProbe: XCTestCase {
    func testReturnFromAnotherApp() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let env = ProcessInfo.processInfo.environment
        let out = env["HOP_ROTATE_OUT"] ?? NSTemporaryDirectory()
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchEnvironment["HOP_DEV_OPEN"] = env["HOP_PROBE_SESSION"] ?? "wake-probe"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_KBLOG_MARKER"] = out + "/wake-kblog.txt"
        app.launch()
        sleep(8)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let c = springboard.descendants(matching: .button).matching(identifier: "Cancel").firstMatch
            guard c.exists else { break }
            c.tap(); sleep(1)
        }
        func shot(_ n: String) {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out + "/wake-\(n).png"))
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "no keyboard on open")
        shot("0-open")
        for i in 1...3 {
            XCUIDevice.shared.press(.home)
            sleep(5)
            app.activate()
            sleep(5)
            shot("\(i)-back")
            // A tap logs "terminal shifted" if the view's top is off screen.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
            sleep(1)
        }
    }
}
