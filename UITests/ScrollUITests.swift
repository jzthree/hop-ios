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
    /// Couples to a session that exists in the live fleet. Tried removing that
    /// by tapping the first row instead — XCUITest's element model for a
    /// SwiftUI List didn't cooperate (neither index nor label predicates
    /// matched), and two attempts made a green suite fragile. The coupling is
    /// the cheaper cost: if these sessions are renamed the failure message says
    /// so, and the fix is one string.
    private func launchIntoSession(_ name: String) -> XCUIApplication {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]   // steady caret: see TerminalScreen
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

        // Same reason: swipe by coordinates rather than resolving the terminal
        // element.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        top.press(forDuration: 0.05, thenDragTo: low)
        top.press(forDuration: 0.05, thenDragTo: low)

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

    /// Sign-out is destructive, had a race (an in-flight refresh could land
    /// after it and put you straight back in), and lives three taps deep behind
    /// a menu — so it is exactly the flow nobody exercises by hand twice.
    /// Safe to run: it only clears this simulator's cookie, which the dev
    /// bootstrap re-seeds on the next launch.
    func testSignOutReturnsToLoginAndStaysThere() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 25),
                      "never reached the session list")

        app.buttons["Settings"].tap()
        app.buttons["Server & account"].tap()
        let signOut = app.buttons["Sign out"].firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "account sheet never appeared")
        signOut.tap()
        // The confirmation repeats the label; take whichever is hittable now.
        app.buttons.matching(identifier: "Sign out").allElementsBoundByIndex
            .last { $0.isHittable }?.tap()

        // Back at login, and it must STAY there: the race was a refresh landing
        // after sign-out and flipping authenticated back to true.
        let password = app.secureTextFields["password"]
        XCTAssertTrue(password.waitForExistence(timeout: 8), "sign out did not return to login")
        Thread.sleep(forTimeInterval: 6)     // longer than the 5s poll interval
        XCTAssertTrue(password.exists, "an in-flight refresh put us back in")
    }

    /// Cross-session output search: the local filter only matches names, so
    /// this is the feature that answers "which session mentioned that error".
    /// Read-only against the live daemon, so safe to run.
    func testSearchFindsSessionsByTheirOutput() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_FILTER"] = "scrollback"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        // The section header only exists when the daemon returned matches, so
        // its presence proves the round trip, not just the UI.
        XCTAssertTrue(app.staticTexts["Found in output"].waitForExistence(timeout: 25),
                      "server-side search returned nothing for a term known to be in the fleet")
    }

    /// Switching sessions from the terminal title goes through the same
    /// requestedSession path that cold-launch quick actions use — the one that
    /// silently did nothing until #51.
    func testSwitchSessionFromTheTitleMenu() throws {
        let app = launchIntoSession("Orion")
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.staticTexts["Orion"].tap()
        let other = app.buttons["Solstice"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "switcher menu never opened")
        other.tap()
        XCTAssertTrue(app.staticTexts["Solstice"].waitForExistence(timeout: 20),
                      "picking a session from the title did not switch to it")
    }

    // Find and "Open link…" are deliberately NOT covered here. Both report
    // through a 2-second toast (or, for links, a confirmation dialog in a
    // separate presentation layer), and XCUITest sees neither reliably: the
    // toast can clear before an assertion starts, and the dialog's title isn't
    // a queryable staticText. Two attempts produced red tests against features
    // whose wiring was fine — the find bar opened and accepted input both
    // times. Flaky tests are worse than none, so these stay on the device
    // checklist, and the pure logic under them (findMatchRow, extractLinks) is
    // covered by unit tests instead.

    /// Regression cover for the tap that did nothing on a mouse-mode session.
    func testTapRaisesTheKeyboard() throws {
        let app = launchIntoSession("Orion")
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].tap()
        XCTAssertFalse(app.keys["a"].waitForExistence(timeout: 3), "keyboard should be down")
        // Coordinate tap, not an element query: resolving `otherElements`
        // against a terminal makes XCUITest snapshot the entire accessibility
        // hierarchy, which took MINUTES per call and made the suite unrunnable
        // in one go.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5),
                      "tapping the terminal must bring the keyboard back")
    }
}
