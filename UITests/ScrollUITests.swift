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
    /// THE fixture session. One constant, per the coupling convention: when
    /// the fleet churns (it did — Orion and Titan vanished daemon-side on
    /// 2026-07-28), the fix is this one string, or the HOP_E2E_FIXTURE env.
    static let fixture = ProcessInfo.processInfo.environment["HOP_E2E_FIXTURE"] ?? "Meridian"

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
        // Named fixtures rot: this pointed at "presenceprobe" until that
        // session was killed, and then failed in a way that read like a scroll
        // regression. Worse, it only ever passed because attaching to a dead
        // name CREATED it — the resurrection bug fixed in #118. A missing
        // session is an environment fact, so skip rather than fail.
        let app = launchIntoSession(Self.fixture)
        // The key bar only exists inside a session, so it's the signal that
        // navigation landed rather than a guess at timing.
        try XCTSkipUnless(app.buttons["escape"].waitForExistence(timeout: 25),
                          "no shell session to scroll — fixture is gone, not a regression")

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
        let app = launchIntoSession(Self.fixture)
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
        let app = launchIntoSession(Self.fixture)
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

    /// The wall's "Copy screen": share what a session shows without entering
    /// it. The menu item existing and the copy producing content are
    /// different claims — the item is gated on the screens store, and a gate
    /// bug would leave a button that writes nothing. The content is read
    /// through a DEBUG marker file: since iOS 16 the runner's own pasteboard
    /// reads are silently denied (background paste privacy), which this test
    /// spent two red runs proving.
    func testCopyScreenFromTheWallProducesTheScreen() throws {
        let marker = "/tmp/hop-copy-marker.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_COPY_MARKER"] = marker
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 25),
                      "never reached the wall")
        // The wall sorts by recency, so a quiet fixture sinks below the fold —
        // and a lazy list has no element for what it hasn't materialized.
        // Seek by scrolling rather than assuming it's on the first screen.
        let cell = app.staticTexts[Self.fixture].firstMatch
        for _ in 0..<6 where !cell.exists { app.swipeUp() }
        try XCTSkipUnless(cell.waitForExistence(timeout: 5),
                          "fixture not in the fleet — environment, not regression")
        // The item appears only once /preview has landed in the screens
        // store; the long-press may need a retry while that poll completes.
        let copy = app.buttons["Copy screen"]
        for _ in 0..<4 where !copy.exists {
            cell.press(forDuration: 0.7)
            if copy.waitForExistence(timeout: 4) { break }
            // Dismiss a menu that opened before the screens store had this
            // session, wait out another poll, try again.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            sleep(2)
        }
        XCTAssertTrue(copy.exists, "Copy screen never appeared in the context menu")
        copy.tap()
        // The menu item's action runs after the dismiss animation — poll.
        var pasted = ""
        for _ in 0..<16 where pasted.isEmpty {
            usleep(500_000)
            pasted = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        }
        XCTAssertFalse(pasted.isEmpty, "Copy screen produced no content")
        XCTAssertFalse(pasted.hasSuffix(" "), "trailing padding survived the trim")
    }

    /// Handoff: opening a session must donate an activity whose webpageURL
    /// is hop web's ?room= deep link for the SAME identifier the daemon
    /// uses. Verified through the DEBUG marker (the donation itself is
    /// system state the runner can't inspect).
    func testOpenSessionDonatesHandoffDeepLink() throws {
        let internalName = ProcessInfo.processInfo
            .environment["HOP_E2E_FIXTURE_INTERNAL"] ?? "Meridian"
        let marker = "/tmp/hop-handoff-marker.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = internalName
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_HANDOFF_MARKER"] = marker
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        var donated = ""
        for _ in 0..<10 where donated.isEmpty {
            usleep(500_000)
            donated = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        }
        XCTAssertTrue(donated.contains("/s/\(internalName)/"),
                      "donated URL missing the session path: \(donated)")
        XCTAssertTrue(donated.hasPrefix("https://"),
                      "handoff URL must be a web URL Safari can open: \(donated)")
    }

    /// Share screen: the system sheet must actually present with the
    /// session's content. The sheet is in-process (unlike the selection
    /// menu), so this is testable — and the dismiss path matters as much,
    /// since a stuck share sheet would wedge the wall.
    func testShareScreenPresentsTheSystemSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 25),
                      "never reached the wall")
        let cell = app.staticTexts[Self.fixture].firstMatch
        for _ in 0..<6 where !cell.exists { app.swipeUp() }
        try XCTSkipUnless(cell.waitForExistence(timeout: 5),
                          "fixture not in the fleet — environment, not regression")
        let share = app.buttons["Share screen…"]
        for _ in 0..<4 where !share.exists {
            cell.press(forDuration: 0.7)
            if share.waitForExistence(timeout: 4) { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            sleep(2)
        }
        XCTAssertTrue(share.exists, "Share screen never appeared in the context menu")
        share.tap()
        // The sheet renders IN-process but its actions are CELLS
        // (actionGroupCell, label "Copy"), not Buttons — a tree dump while
        // the sheet was visibly up proved app.buttons["Copy"] matches
        // nothing. Query the cell by label.
        let sheetLandmark = app.cells.matching(
            NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(sheetLandmark.waitForExistence(timeout: 8),
                      "share sheet never presented")
        // Dismiss (tap the dimmed wall above the sheet) and confirm usable.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 8),
                      "wall unusable after dismissing the share sheet")
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

    // Find and "Open link…" are deliberately NOT covered here. Both report
    // through a 2-second toast (or, for links, a confirmation dialog in a
    // separate presentation layer), and XCUITest sees neither reliably: the
    // toast can clear before an assertion starts, and the dialog's title isn't
    // a queryable staticText. Two attempts produced red tests against features
    // whose wiring was fine — the find bar opened and accepted input both
    // times. Flaky tests are worse than none, so these stay on the device
    // checklist, and the pure logic under them (findMatchRow, extractLinks) is
    // covered by unit tests instead.

    /// Reconnect used to cost TWO connections: cancelling the old socket left
    /// its pending receive to fire as a failure, which scheduled a retry a
    /// second later. The count itself is only visible in the log
    /// (`snapshot N KB`, measured 3 → 2), so what this asserts is the part
    /// XCUITest can see — that the session stays usable across it, which the
    /// second teardown was quietly disrupting.
    func testReconnectKeepsTheSessionUsable() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["Terminal actions"].tap()
        app.buttons["Reconnect"].tap()
        Thread.sleep(forTimeInterval: 6)   // longer than the old 1s spurious retry
        XCTAssertTrue(app.buttons["escape"].exists, "key bar gone after reconnect")
        XCTAssertTrue(app.buttons["down arrow"].exists, "key bar gone after reconnect")
    }

    /// Swipe-to-reply, verified up to the point of sending — the dialog opens
    /// and cancels. Deliberately does NOT send: input to a live agent session
    /// could approve something, and no test is worth that.
    func testSwipeToReplyOpensAndCancels() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        // The CELL containing the label, not the label: swipe actions belong
        // to the row, and swiping a text element inside it does nothing.
        let label = app.staticTexts[Self.fixture].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 25), "session list never loaded")
        let row = app.cells.containing(.staticText, identifier: Self.fixture).element
        row.swipeRight()
        let reply = app.buttons["Reply"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "leading swipe offered no Reply")
        reply.tap()
        // The alert became a SHEET with a context snippet and a mono
        // composer; drag-down is its cancel.
        XCTAssertTrue(app.textFields["Answer…"].waitForExistence(timeout: 5),
                      "Reply did not open the compose sheet")
        app.swipeDown(velocity: .fast)
        XCTAssertFalse(app.textFields["Answer…"].waitForExistence(timeout: 2),
                       "dismissing the sheet left it up")
    }

    /// An agent session has no local scrollback, so this asserts the only thing
    /// visible from here: that a drag doesn't crash and the session stays
    /// usable. What it actually sends (wheel events) is verified in the log —
    /// `scroll back N via wheel` — since XCUITest cannot see into a terminal.
    func testDragOnAgentSessionKeepsSessionUsable() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        top.press(forDuration: 0.05, thenDragTo: low)
        XCTAssertTrue(app.buttons["escape"].exists, "key bar gone after a drag")
        XCTAssertTrue(app.buttons["down arrow"].exists, "key bar gone after a drag")
    }

    /// Regression cover for the tap that did nothing on a mouse-mode session.
    func testTapRaisesTheKeyboard() throws {
        let app = launchIntoSession(Self.fixture)
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

    /// A flick has to keep scrolling after the finger leaves, or the terminal
    /// feels like a document viewer from 2008. XCUITest can't see into the
    /// terminal, so this asserts the session survives a hard flick; that the
    /// coast reaches the remote app is verified in the log, where wheel events
    /// keep arriving for about a second after the gesture ends.
    func testFlickKeepsSessionUsable() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["escape"].exists, "key bar gone after a flick")
        XCTAssertTrue(app.staticTexts[Self.fixture].exists, "session title gone after a flick")
    }

    /// The swipe back to the session list must not double as a scroll. Our pan
    /// covers the whole terminal, so without yielding to the edge gesture the
    /// way out of a session also flings wheel events at the agent — and with
    /// momentum, keeps flinging them after the screen is gone.
    func testSwipeBackLeavesTheSessionInsteadOfScrolling() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: right)
        // Back at the list: the key bar is gone and sessions are listed again.
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 10),
                      "swipe from the edge didn't leave the session")
        XCTAssertFalse(app.buttons["escape"].exists, "key bar survived the swipe back")
    }

    /// Touching a coasting terminal must STOP it and do nothing else, the way
    /// every scroll view on iOS behaves. The failure this pins is specific:
    /// without the brake, the tap that stops a coast also raises the keyboard,
    /// which shrinks the screen you were reading.
    func testTapDuringCoastOnlyStopsIt() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].tap()
        XCTAssertFalse(app.keys["a"].waitForExistence(timeout: 3), "keyboard should be down")

        app.swipeDown(velocity: .fast)
        // Inside the coast (about a second): this touch is a brake.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertFalse(app.keys["a"].waitForExistence(timeout: 2),
                       "a tap that stops a coast must not also raise the keyboard")

        // ...and the very next tap is an ordinary tap again.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5),
                      "tapping a stopped terminal must still raise the keyboard")
    }

    /// A create the daemon refuses must stay on screen. It used to be written
    /// into the same field as connectivity errors, which a successful poll
    /// clears — so the verdict on something you just did vanished in under
    /// five seconds, often before it was read.
    func testRejectedActionStaysVisibleThroughPolls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 25))
        app.buttons["New session"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.typeText(Self.fixture)                      // a name already taken
        app.buttons["Create"].tap()

        let refusal = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'already in use'")).firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 10),
                      "the daemon's reason was never shown")
        // Survive two poll cycles — the thing that used to erase it.
        sleep(12)
        XCTAssertTrue(refusal.exists, "the refusal was wiped by a successful poll")
    }

    /// Holding a key drives a Timer that asserts it runs on the main actor
    /// (#112c). If that assertion is ever wrong the app TRAPS rather than
    /// misbehaving, so this holds the key and checks the app is still there.
    func testHoldToRepeatDoesNotTrap() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        let down = app.buttons["down arrow"].firstMatch
        XCTAssertTrue(down.waitForExistence(timeout: 5), "no down key in the bar")
        down.press(forDuration: 1.6)          // drives the repeat timer
        sleep(2)
        XCTAssertTrue(app.buttons["escape"].exists, "the app died holding a key")
        XCTAssertTrue(app.buttons["down arrow"].exists)
    }

    /// The summary line is the bell's last resort: it can read "1 wants you
    /// (1 not shown here)" precisely when scope or filter hides the ringing
    /// session — and until now it offered no way to reach it. Tapping it must
    /// open that session, ignoring whatever the list is hiding.
    func testWantsYouSummaryOpensTheHiddenSession() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] =
            ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_ATTENTION"] = "1"     // force one bell
        app.launchEnvironment["HOP_DEV_FILTER"] = "zzz-no-match"  // hide it
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        // A BUTTON, not a static text: SwiftUI collapses the Text into the
        // button's accessibility element. The first version of this test
        // queried staticTexts, passed once standalone (the hierarchy happened
        // to expose both), then failed in the suite — and the dump showed the
        // summary present the whole time, wearing button clothes.
        let summary = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'not shown here'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 25),
                      "hidden-bell summary never appeared")
        summary.tap()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25),
                      "tapping the wants-you summary did not open the session")
    }

    /// Opening Find must move the keyboard to the find field. It used to stay
    /// bound to the terminal, so typing a search term sent it into the live
    /// session — a claude composer received "keyboard" while the find field
    /// sat empty. Asserting on the FIELD's value keeps this away from the
    /// flaky match-toast territory that kept find otherwise untested.
    func testFindFocusesItsFieldNotTheTerminal() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["Terminal actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Find"].waitForExistence(timeout: 5))
        app.buttons["Find"].tap()
        sleep(1)
        app.typeText("zebra")
        let field = app.textFields["find in scrollback"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "zebra",
                       "typing after opening Find must land in the find field")
    }

}
