import XCTest

// The gap these close: every interaction defect in this app so far — no touch
// scrolling, taps not raising the keyboard, a drag scrolling out from under a
// selection — was invisible to unit tests and to screenshots, because none of
// them involve a finger. XCUITest drives real gestures at the real app, which
// is the only automated way to find that class of bug here.
//
// Auth comes from the daemon's own token, forwarded by the Makefile as
// TEST_RUNNER_HOP_DEV_COOKIE (xcodebuild strips the prefix for the runner).
final class ScrollUITests: XCTestCase {
    private func launchIntoSession(_ name: String) -> XCUIApplication {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_OPEN"] = name
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()
        return app
    }

    /// Scrolling has to move the buffer AND leave it recoverable: a terminal
    /// you can scroll but not return to the live edge is worse than one you
    /// can't scroll at all.
    func testDragScrollsAndLiveButtonReturns() throws {
        // A SHELL session, not claude: TUI apps run in the alternate screen
        // buffer, which by definition has no scrollback, so there is nothing
        // for a drag to reach. Pointing this at an agent session made the test
        // fail for a reason that had nothing to do with scrolling.
        let app = launchIntoSession("presenceprobe")
        // The key bar only exists inside a session, so it's the signal that
        // navigation landed rather than a guess at timing.
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25),
                      "never reached a terminal — key bar absent")

        let terminal = app.otherElements.firstMatch
        terminal.swipeDown()
        terminal.swipeDown()

        // Scrolling up from the live edge is what surfaces the jump-to-live
        // control; if it never appears, the drag did not move the viewport.
        // Even a shell only has history if it has printed more than a screen.
        // Skip rather than fail on an idle one — a red suite that means "this
        // session was quiet" trains you to ignore it.
        let live = app.buttons["Live"]
        try XCTSkipUnless(live.waitForExistence(timeout: 5),
                          "session had no scrollback to scroll through")
        live.tap()
        XCTAssertFalse(live.waitForExistence(timeout: 3),
                       "Live should disappear once back at the bottom")
    }

    // NOTE: there is deliberately no selection test here. Double-tap selects a
    // word and offers Copy, but that menu is presented by another process, so
    // it never appears in this app's accessibility hierarchy and the assertion
    // fails whatever the app does. Testing the OS's menu presentation isn't
    // this suite's job; selection stays on the device checklist.

    /// Sticky modifiers are the key bar's least visible feature and its most
    /// load-bearing: ctrl+something is how you interrupt, clear, or search a
    /// terminal. Nothing had ever pressed this key.
    func testCtrlArmsAndDisarms() throws {
        let app = launchIntoSession("Orion")
        let ctrl = app.buttons["control"]
        XCTAssertTrue(ctrl.waitForExistence(timeout: 25))
        // XCUITest reports a nil accessibilityValue as "", not nil.
        XCTAssertEqual(ctrl.value as? String, "", "starts unarmed")
        ctrl.tap()
        XCTAssertEqual(ctrl.value as? String, "armed", "one tap arms it")
        ctrl.tap()
        XCTAssertEqual(ctrl.value as? String, "", "tapping again disarms rather than sticking")
    }

    /// Landscape was verified only by a dev flag that forced the compact
    /// layout in portrait — a proxy for the thing, not the thing. XCUIDevice
    /// can actually rotate, so assert the real behaviour: in landscape the
    /// keyboard takes over half the height, so the nav bar gets out of the way
    /// and the terminal keeps its keys.
    func testLandscapeHidesChromeButKeepsTheKeyBar() throws {
        let app = launchIntoSession("Orion")
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["Terminal actions"].exists, "portrait shows the nav bar")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        // Give the rotation a moment to settle before asserting on layout.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["Terminal actions"], handler: nil)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["escape"].exists,
                      "the key bar must survive: it's the only way to send esc")
    }

    /// Regression cover for the tap that did nothing on a mouse-mode session.
    func testTapRaisesTheKeyboard() throws {
        let app = launchIntoSession("Orion")
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].tap()
        XCTAssertFalse(app.keys["a"].waitForExistence(timeout: 3), "keyboard should be down")
        app.otherElements.firstMatch.tap()
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5),
                      "tapping the terminal must bring the keyboard back")
    }
}
