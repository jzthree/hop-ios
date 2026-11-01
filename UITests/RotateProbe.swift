import XCTest
/// Rotate portrait ⇄ landscape on a session that prints its PTY size, and
/// shoot each state — "size is wrong after switching back and forth".
/// Needs a session named rotate-probe2 running a loop that clears with ED3
/// and prints its `tput` size every second (STATUS.md 2026-10-31).
final class RotateProbe: XCTestCase {
    func testRotateBackAndForth() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let out = ProcessInfo.processInfo.environment["HOP_ROTATE_OUT"] ?? NSTemporaryDirectory()
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchEnvironment["HOP_DEV_OPEN"] = "rotate-probe2"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_KBLOG_MARKER"] = out + "/rot-kblog.txt"
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        sleep(8)
        // The simulator's own "Sign in to Apple Account" prompt makes the app
        // INACTIVE, and an inactive app claims nothing — clear it first.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        try? (springboard.debugDescription + "\n=====APP\n" + app.debugDescription).write(toFile: out + "/rot-tree.txt", atomically: true, encoding: .utf8)
        for _ in 0..<3 {
            let c = springboard.descendants(matching: .button).matching(identifier: "Cancel").firstMatch
            guard c.exists else { break }
            c.tap(); sleep(1)
        }
        for _ in 0..<3 {
            let c = app.descendants(matching: .button).matching(identifier: "Cancel").firstMatch
            guard c.exists else { break }
            c.tap(); sleep(1)
        }
        // Own the size, as on a phone you type into.
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Session is'")).firstMatch
        if chip.waitForExistence(timeout: 4) { chip.tap() }
        sleep(4)
        func shot(_ n: String) {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out + "/rot-\(n).png"))
        }
        shot("0-portrait")
        for i in 1...3 {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(4); shot("\(i)a-landscape")
            XCUIDevice.shared.orientation = .portrait
            sleep(4); shot("\(i)b-portrait")
            sleep(1); shot("\(i)c-portrait")
        }
    }
}
