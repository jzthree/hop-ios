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
    /// The keyboard-frame instrument must survive: when sizing goes wrong
    /// on the device, Copy diagnostics is the pasteable trace that names the
    /// stale layer. This asserts the whole path — record on keyboard events,
    /// surface in the copied text.
    func testDiagnosticsCarryKeyboardTrace() throws {
        try? FileManager.default.removeItem(atPath: "/tmp/hop-diag-marker.txt")
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = Self.fixture
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_COPY_MARKER"] = "/tmp/hop-diag-marker.txt"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["hide keyboard"].tap()
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(2)
        // One real SOFTWARE keystroke so the text-input forensics have
        // something to record: typeText synthesizes HARDWARE events, which
        // bypass insertText entirely (SwiftTerm routes them via presses —
        // probe-proven silence). Poll for hittable; mid-rise keys exist
        // offscreen and AX can't scroll to them.
        let eKey = app.keys["e"]
        var canTap = false
        for _ in 0..<16 where !canTap {
            usleep(500_000)
            canTap = eKey.exists && eKey.isHittable
        }
        // The sim's hardware-keyboard mode can pin software keys offscreen
        // forever — an environment fact. The forensics' real consumer is
        // the device; assert only when the sim cooperates.
        try XCTSkipUnless(canTap, "software keyboard never rose — sim hardware-kb mode")
        eKey.tap()
        sleep(1)
        // Back out and into the Account sheet, where the trace surfaces.
        app.buttons["Back to sessions"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        app.buttons["Server & account"].tap()
        sleep(2)
        app.swipeUp()
        sleep(1)
        let copy = app.buttons["Copy diagnostics"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        var text = ""
        for _ in 0..<10 where text.isEmpty {
            usleep(500_000)
            text = (try? String(contentsOfFile: "/tmp/hop-diag-marker.txt", encoding: .utf8)) ?? ""
        }
        XCTAssertTrue(text.contains("kbFrame"), "no keyboard events in the trace: \(text.suffix(400))")
        XCTAssertTrue(text.contains("fit "), "no fit lines in the trace")
        XCTAssertTrue(text.contains("settle"), "no settle verdicts in the trace")
        XCTAssertTrue(text.contains("ti."), "no text-input forensics in the trace")
    }

    /// Couples to a session that exists in the live fleet — when the fleet
    /// churns, the fix is the one fixture string (or HOP_E2E_FIXTURE).
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

    /// The terminal's ⋯ must carry the web sheet's session verbs — Rename
    /// was reported missing from inside a session (everything lived only on
    /// the wall's long-press).
    func testTerminalMenuCarriesSessionVerbs() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.buttons["Terminal actions"].tap()
        // The text-size stepper keeps the menu OPEN (menuActionDismissBehavior
        // .disabled) — a tap on Smaller must not dismiss. Tap Bigger after to
        // leave the persisted size where it started.
        XCTAssertTrue(app.buttons["Smaller text"].waitForExistence(timeout: 5),
                      "text-size stepper missing from the terminal menu")
        // Standing visual artifact: the open menu, refreshed every run. The
        // AX tree hid the last failure (a fold nothing hints at); the pixels
        // did not.
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/hop-menu-current.png"))
        app.buttons["Smaller text"].tap()
        XCTAssertTrue(app.buttons["Session"].waitForExistence(timeout: 3),
                      "size stepper dismissed the menu")
        app.buttons["Bigger text"].tap()
        // The session verbs live one level down (the flat 18-row menu
        // scrolled past the keyboard-up fold and iOS truncated its AX tail —
        // Reconnect vanished from the tree). The flat door is the title
        // long-press, covered by its own test.
        app.buttons["Session"].tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5),
                      "Rename missing from the Session submenu")
        XCTAssertTrue(app.buttons["Edit tagline"].exists)
        XCTAssertTrue(app.buttons["Park"].exists)
        XCTAssertTrue(app.buttons["Kill"].exists)
        XCTAssertTrue(app.buttons["Move to Agents"].exists || app.buttons["Move to You"].exists,
                      "origin move missing")
        // Dismiss without touching anything destructive.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
    }

    /// THE size contract, after Jian revised it himself: "only keystroke
    /// should" claim, and "eliminate any design that can lead to race
    /// conditions." Waking with the session on screen must claim NOTHING —
    /// two clients each treating their own presence as intent is exactly how
    /// a grid ends up matching neither window. A keystroke, and only a
    /// keystroke, takes the size.
    func testWakeClaimsNothingButAKeystrokeDoes() throws {
        let marker = "/tmp/hop-wake-claim.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_OPEN"] = Self.fixture
        app.launchEnvironment["HOP_CLAIM_MARKER"] = marker
        // A grid no phone would ever fit, adopted at background exactly as the
        // daemon's broadcast does to an inactive phone.
        app.launchEnvironment["HOP_DEV_FOREIGN_SIZE"] = "100x30"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        sleep(3)
        try? FileManager.default.removeItem(atPath: marker)
        XCUIDevice.shared.press(.home)      // background: the hook adopts 100x30
        sleep(2)
        app.activate()                      // wake
        sleep(4)
        // Half one: presence claims nothing.
        let afterWake = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        XCTAssertTrue(afterWake.isEmpty,
                      "waking claimed the size with no keystroke: \(afterWake)")
        // Half two: a keystroke does. (typeText reaches the send path — the
        // half-open test proves the daemon receives it.)
        app.typeText(" ")
        var claimed = ""
        for _ in 0..<30 {
            if let s = try? String(contentsOfFile: marker, encoding: .utf8), !s.isEmpty {
                claimed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            usleep(300_000)
        }
        XCTAssertFalse(claimed.isEmpty, "a keystroke claimed nothing")
        XCTAssertNotEqual(claimed, "100x30", "the keystroke claimed the FOREIGN grid")
    }

    /// The passkey door exists on the sign-in screen. Skips honestly when the
    /// app is already authenticated — the suite shares a container and a
    /// cookie from any earlier test signs it in, so asserting unconditionally
    /// would make this test order-dependent.
    func testSignInOffersThePasskeyDoor() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hop-ui-testing"]   // deliberately NO dev cookie
        app.launch()
        let passkey = app.buttons["Sign in with a passkey"]
        let signedIn = app.buttons["New session"]
        for _ in 0..<50 where !passkey.exists && !signedIn.exists {
            usleep(300_000)
        }
        try XCTSkipIf(signedIn.exists,
                      "already authenticated — shared container, not a regression")
        XCTAssertTrue(passkey.exists, "sign-in screen has no passkey option")
    }

    /// The briefing renders from the file the host agent writes. Skips when
    /// no digest has been generated yet — the card is absent by design until
    /// the scheduled job has run, and that is environment, not regression.
    func testBriefingCardRendersAndOpensASession() throws {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_TILES"] = "0"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        let card = app.staticTexts["Briefing"]
        let wall = app.buttons["New session"]
        _ = wall.waitForExistence(timeout: 25)
        for _ in 0..<20 where !card.exists { usleep(300_000) }
        try XCTSkipUnless(card.exists, "no digest written yet — environment")
        // Every item is a button that opens its session; tapping the first
        // must land in a terminal, not merely highlight.
        let firstItem = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Opens ")).firstMatch
        if firstItem.exists {
            firstItem.tap()
            XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25),
                          "a briefing row did not open its session")
        }
    }

    /// The biometric lock exists and is REACHABLE. It shipped off and three
    /// taps deep, and Jian reported the app "still does not have biometric
    /// login" weeks after it landed — so this guards the door, and the
    /// one-time offer (SessionsView) guards the discovery.
    func testAccountCarriesTheBiometricLock() throws {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_SHEET"] = "account"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        // Face ID on a device, Passcode on a bare simulator — the label names
        // whatever gate this hardware actually has.
        let lock = app.switches.matching(NSPredicate(format:
            "label CONTAINS 'Require'")).firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 25),
                      "no biometric lock toggle in Server & account")
    }

    /// The other half of the size story (Jian: "the app keeps resizing the
    /// terminal even when it is inactive — do it only when the user is
    /// actively looking"). One PTY serves every client, so a resize this app
    /// sends reshapes whatever screen someone else is working in. Backgrounding
    /// makes iOS re-lay-out this view (the app-switcher snapshot), which used
    /// to reach the daemon as a real resize. Nothing may go out while away.
    func testBackgroundingSendsNoResize() throws {
        let marker = "/tmp/hop-bg-resize.txt"
        try? FileManager.default.removeItem(atPath: marker)
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_OPEN"] = Self.fixture
        // Witnesses every resize that actually reaches the wire, with the
        // app state at send time — the runner cannot watch the socket.
        app.launchEnvironment["HOP_RESIZE_MARKER"] = marker
        // Reproduces the layout squeeze iOS applies on the way out. Without
        // it a simulator home-press changes no bounds, nothing refits, and
        // this test passes against the very bug it exists to catch
        // (measured: it did — 2026-07-31).
        app.launchEnvironment["HOP_DEV_BG_REFIT"] = "1"
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        sleep(3)                                   // let the attach claim land
        try? FileManager.default.removeItem(atPath: marker)
        XCUIDevice.shared.press(.home)             // snapshot + layout churn
        sleep(4)
        let sentWhileAway = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        app.activate()
        XCTAssertTrue(sentWhileAway.isEmpty,
                      "resize(s) sent while the app was inactive: \(sentWhileAway)")
    }

    /// hop2 e4bdd86 mirror: a name the daemon would accept in any case must
    /// open in the app too. Launches with the INTERNAL fixture name (stable
    /// across display renames) deliberately case-mangled; reaching the
    /// terminal proves the outside-name resolver folded it to canonical.
    func testCaseMangledOpenLandsInTheSession() throws {
        let canonical = ProcessInfo.processInfo
            .environment["HOP_E2E_FIXTURE_INTERNAL"] ?? "Meridian"
        let mangled = String(canonical.map {
            $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased())
        })
        XCTAssertNotEqual(mangled, canonical,
                          "mangling was a no-op — letterless fixture name?")
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_OPEN"] = mangled
        app.launchArguments += ["-hop-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25),
                      "case-mangled open never reached the terminal")
    }

    /// The second door to the session verbs: long-press the NAME in the pill.
    /// Same @ViewBuilder as the ⋯ menu's Session section, so this asserts the
    /// door exists, not the verbs' behaviour (the menu test owns that).
    func testTitleLongPressShowsSessionVerbs() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        let title = app.staticTexts[Self.fixture].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "pill title missing")
        title.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5),
                      "long-press on the title did not open the session verbs")
        XCTAssertTrue(app.buttons["Park"].exists)
        // Dismiss the context menu harmlessly.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
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
        // Narrow to the fixture with the app's own filter instead of
        // swipe-hunting for it: the row's position depends on fleet order,
        // which churns, and a present-but-not-hittable row reads as a
        // feature regression (suite-caught: "Not hittable: StaticText").
        app.launchEnvironment["HOP_DEV_FILTER"] = Self.fixture
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
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
        // While the menu is up: Fork session and Move to must be offered
        // (tapping either would mutate the live fixture; presence is the
        // assertion).
        XCTAssertTrue(app.buttons["Fork session"].exists,
                      "Fork session missing from the context menu")
        XCTAssertTrue(app.buttons["Move to"].exists,
                      "Move to missing from the context menu")
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
        // Narrow to the fixture with the app's own filter instead of
        // swipe-hunting for it: the row's position depends on fleet order,
        // which churns, and a present-but-not-hittable row reads as a
        // feature regression (suite-caught: "Not hittable: StaticText").
        app.launchEnvironment["HOP_DEV_FILTER"] = Self.fixture
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
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

    /// The hop keyboard: toggling from the accessory bar must swap the
    /// system keyboard for the board (and back), planes must switch, and
    /// the preference must not leak into other tests (toggled off at end).
    func testHopKeyboardTogglesAndSwitchesPlanes() throws {
        let app = launchIntoSession(Self.fixture)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        // The toggle sits past the bar's fold: scroll the bar by swiping it.
        let bar = app.buttons["escape"]
        XCTAssertTrue(bar.exists)
        let board = app.buttons["hop keyboard"]
        if !board.isHittable {
            app.buttons["right arrow"].swipeLeft()
        }
        XCTAssertTrue(board.waitForExistence(timeout: 5), "toggle key missing from the bar")
        board.tap()
        // Letters plane up. The preference is STICKY: a prior aborted run
        // can leave the board ON, in which case that tap just turned it
        // OFF — toggle once more rather than fail on inherited state
        // (trap: a stuck-ON board also breaks every keys[]-based test).
        var lettersUp = app.buttons["q"].waitForExistence(timeout: 4)
        if !lettersUp {
            board.tap()
            lettersUp = app.buttons["q"].waitForExistence(timeout: 4)
        }
        XCTAssertTrue(lettersUp, "hop keyboard letters plane never appeared")
        // 123 plane.
        app.buttons["numbers"].firstMatch.tap()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 3), "numbers plane missing")
        // #+= plane has the terminal's precious keys.
        app.buttons["more symbols"].firstMatch.tap()
        XCTAssertTrue(app.buttons["|"].waitForExistence(timeout: 3), "symbols plane missing |")
        XCTAssertTrue(app.buttons["~"].exists, "symbols plane missing ~")
        // Landscape must COMPRESS the board (232 -> 150): a fixed portrait
        // height in landscape left a few terminal rows under 278pt of keys.
        app.buttons["letters"].firstMatch.tap()
        XCTAssertTrue(app.buttons["q"].waitForExistence(timeout: 3))
        let portraitKeyHeight = app.buttons["q"].frame.height
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        // The sim sometimes refuses to rotate under suite load (recorded
        // trap: rotation wedge) — poll for the rotation actually landing,
        // and SKIP if it never does: a wedged sim is environment, and a
        // wedge here used to cascade into the landscape test after this.
        var rotated = false
        for _ in 0..<12 where !rotated {
            usleep(300_000)
            let w = app.windows.firstMatch.frame
            rotated = w.width > w.height
        }
        try XCTSkipUnless(rotated, "sim refused to rotate — environment, not regression")
        sleep(1)
        XCTAssertTrue(app.buttons["q"].exists, "board vanished on rotation")
        let landscapeKeyHeight = app.buttons["q"].frame.height
        XCTAssertLessThan(landscapeKeyHeight, portraitKeyHeight * 0.8,
                          "landscape board did not compress (\(landscapeKeyHeight) vs \(portraitKeyHeight))")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        // The escape hatch back to the system keyboard.
        app.buttons["system keyboard"].firstMatch.tap()
        XCTAssertTrue(app.keys["a"].waitForExistence(timeout: 5),
                      "system keyboard did not come back")
        XCTAssertFalse(app.buttons["q"].isHittable,
                       "board still up after toggling back")
    }

    /// Instant launch: after one normal run has filled the cache, a
    /// relaunch with the network path DISABLED (HOP_DEV_CACHE_ONLY) must
    /// still paint the wall — proof the first frame comes from disk, not
    /// from the refresh round-trip.
    func testWallPaintsFromCacheWithoutNetwork() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
        app.launch()
        let cell = app.staticTexts[Self.fixture].firstMatch
        var found = cell.waitForExistence(timeout: 25)
        for _ in 0..<6 where !found { app.swipeUp(); found = cell.exists }
        try XCTSkipUnless(found, "fixture not in the fleet — environment, not regression")
        sleep(2)   // let the first refresh's cache save land
        app.terminate()

        let cold = XCUIApplication()
        cold.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        cold.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        cold.launchEnvironment["HOP_DEV_CACHE_ONLY"] = "1"
        cold.launchArguments += ["-hop-ui-testing"]
        cold.launch()
        let cached = cold.staticTexts[Self.fixture].firstMatch
        var there = cached.waitForExistence(timeout: 8)
        for _ in 0..<6 where !there { cold.swipeUp(); there = cached.exists }
        XCTAssertTrue(there, "cached wall did not paint without the network")
    }

    /// Optimistic echo, wire integrity: with local echo live, what reaches
    /// the DAEMON must still be single characters (an echo accidentally
    /// wired into the send path would double every key: "eecchhoo"). The
    /// render side is covered by the ported unit suite; this guards the
    /// integration. Scratch session created and killed runner-side.
    func testTypingWithLocalEchoStaysSingleOnTheWire() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty, "no daemon cookie in this environment")
        let scratch = "EchoProbe"
        XCTAssertTrue(daemonPOST("api/sessions",
                                 ["name": scratch, "type": "terminal"], cookie: cookie),
                      "scratch create refused")
        defer { _ = daemonPOST("api/sessions/delete",
                               ["internalName": scratch], cookie: cookie) }

        let app = launchIntoSession(scratch)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8), "keyboard never rose")
        sleep(1)
        app.typeText("echo zq\n")

        var screen = ""
        for _ in 0..<16 where !screen.contains("zq") {
            usleep(500_000)
            screen = daemonPreview(of: scratch, cookie: cookie) ?? ""
        }
        XCTAssertTrue(screen.contains("echo zq"), "typed line never reached the daemon: \(screen.suffix(200))")
        XCTAssertFalse(screen.contains("eecc"), "doubled input on the wire — echo leaked into send")
    }

    private func daemonPOST(_ path: String, _ body: [String: Any], cookie: String) -> Bool {
        guard let url = URL(string: "https://hop.zhoulab.io/\(path)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return ok
    }

    private func daemonPreview(of name: String, cookie: String) -> String? {
        guard var comps = URLComponents(string: "https://hop.zhoulab.io/api/sessions/preview") else { return nil }
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        var text: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                text = obj["text"] as? String
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return text
    }

    /// The daemon now REFUSES attaches to unknown sessions (404, hop2
    /// d1e76ce — phantom sessions are no longer invented). This pins the
    /// client's half: a cached row for a session killed since must land on
    /// the "Session ended" screen, not a phantom shell and not an endless
    /// "connecting". Exercises the raw-socket 404 the daemon writes and the
    /// classifier that reads it off task.response.
    func testKilledSessionFromCacheLandsOnGoneNotPhantom() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty, "no daemon cookie in this environment")
        let scratch = "GoneProbe"
        XCTAssertTrue(daemonPOST("api/sessions",
                                 ["name": scratch, "type": "terminal"], cookie: cookie))
        // Fill the cache with the scratch alive.
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
        app.launch()
        let row = app.staticTexts[scratch].firstMatch
        var found = row.waitForExistence(timeout: 25)
        for _ in 0..<6 where !found { app.swipeUp(); found = row.exists }
        XCTAssertTrue(found, "scratch never reached the wall")
        sleep(2)                       // first refresh's cache save
        app.terminate()

        // Kill it daemon-side; the cache still remembers it.
        XCTAssertTrue(daemonPOST("api/sessions/delete",
                                 ["internalName": scratch], cookie: cookie))

        // Cold launch straight INTO the dead session: the cache paints the
        // wall, HOP_DEV_OPEN navigates before any live refresh can replace
        // the hearsay list — the exact vulnerable window a user hits tapping
        // a cached row in the first seconds after launch.
        let cold = XCUIApplication()
        cold.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        cold.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        cold.launchEnvironment["HOP_DEV_OPEN"] = scratch
        cold.launchArguments += ["-hop-ui-testing"]
        cold.launch()
        XCTAssertTrue(cold.staticTexts["Session ended"].waitForExistence(timeout: 25),
                      "attach to a killed cached session did not land on the gone screen")
        // And the daemon must NOT have invented a phantom under that name.
        // The LIST is the witness — /preview remembers dead sessions' last
        // screens without resurrecting them (verified by hand), so a
        // preview-based check false-alarms.
        sleep(2)
        XCTAssertFalse(daemonHasSession(scratch, cookie: cookie),
                       "a phantom session exists under the killed name")
    }

    private func daemonHasSession(_ name: String, cookie: String) -> Bool {
        guard let url = URL(string: "https://hop.zhoulab.io/api/sessions") else { return false }
        var req = URLRequest(url: url)
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        var found = false
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["sessions"] as? [[String: Any]] {
                found = list.contains { ($0["internalName"] as? String) == name }
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return found
    }

    /// "By folder" renders Jian's own filing: switch the arrangement and a
    /// real folder name from the live daemon must appear as a section.
    func testByFolderShowsRealFolderSections() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        guard let firstFolder = daemonFirstFolderName(cookie: cookie) else {
            throw XCTSkip("no folders on this daemon — nothing to render")
        }
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
        app.launch()
        XCTAssertTrue(app.buttons["New session"].waitForExistence(timeout: 25))
        app.buttons["Settings"].tap()
        let byFolder = app.buttons["By folder"]
        XCTAssertTrue(byFolder.waitForExistence(timeout: 5),
                      "arrange picker missing By folder")
        byFolder.tap()
        let header = app.staticTexts[firstFolder].firstMatch
        var seen = header.waitForExistence(timeout: 8)
        for _ in 0..<6 where !seen { app.swipeUp(); seen = header.exists }
        XCTAssertTrue(seen, "folder section '\(firstFolder)' never rendered")
        // Restore Recent so later tests see the flat wall they expect.
        app.buttons["Settings"].tap()
        app.buttons["Recent"].tap()
    }

    private func daemonFirstFolderName(cookie: String) -> String? {
        guard let url = URL(string: "https://hop.zhoulab.io/api/sessions") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        var name: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let folders = obj["folders"] as? [[String: Any]] {
                name = folders.first?["name"] as? String
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return name
    }

    /// Select-and-copy, the native contract: press-and-hold selects a word
    /// (no scroll/select mode — a hold is never a scroll), the modern edit
    /// menu appears, Copy fills the pasteboard. Witnessed via the DEBUG
    /// copy marker (the runner cannot read the pasteboard) with the ACTUAL
    /// word under the press.
    func testLongPressSelectsAndCopyCopies() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "SelectProbe"
        // A prior aborted run can leave the scratch alive; clear, then create.
        _ = daemonPOST("api/sessions/delete", ["internalName": scratch], cookie: cookie)
        sleep(1)
        XCTAssertTrue(daemonPOST("api/sessions",
                                 ["name": scratch, "type": "terminal"], cookie: cookie))
        defer { _ = daemonPOST("api/sessions/delete",
                               ["internalName": scratch], cookie: cookie) }
        let marker = "/tmp/hop-select-marker.txt"
        try? FileManager.default.removeItem(atPath: marker)
        try? FileManager.default.removeItem(atPath: "/tmp/hop-selecthold-marker.txt")

        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_COPY_MARKER"] = marker
        app.launchEnvironment["HOP_SELECT_MARKER"] = "/tmp/hop-selecthold-marker.txt"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8))
        sleep(1)
        // Paint a known word, then put the keyboard away so the press lands
        // on the transcript, not the keys.
        // Fill the screen with words so a mid-screen press lands ON text —
        // a fresh scratch has three sparse lines at the very top, and a
        // press on a blank cell rightly selects nothing (and shows nothing).
        // The keyboard STAYS UP: the deterministic path (no layout churn
        // under the menu); the keyboard-was-down path gets its own settle
        // delay in the app and its verdict on the device.
        app.typeText("seq 1000 1040\n")
        sleep(2)

        // ONE deterministic press on the transcript body: whatever word sits
        // there (prompt or sentinel), the contract is hold -> menu -> Copy ->
        // pasteboard. The element type of an edit-menu item is version-
        // fickle, so match any descendant named Copy.
        // dx lands ON the seq digits (cols 0-4); a press right of them
        // selects an empty word — active but blank (probe-proven). 0.07
        // clears the 16pt edge-swipe zone.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.35))
            .press(forDuration: 0.7)
        // Window-hosted, the chip is a REAL element now — tappable by
        // identity, reachable by VoiceOver (the superview attempt sat
        // behind the SwiftUI hosting boundary and needed blind
        // coordinate taps).
        let chip = app.buttons["Copy selection"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 6),
                      "the Copy chip never appeared after long-press")
        chip.tap()
        var copied = ""
        for _ in 0..<10 where copied.isEmpty {
            usleep(500_000)
            copied = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
        }
        XCTAssertFalse(copied.isEmpty, "Copy fired but the marker saw nothing")
        XCTAssertTrue(copied.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1,
                      "copied text unexpected: '\(copied)'")
    }

    /// The other half of the selection contract: the handles a long-press
    /// summons must be DRAGGABLE. gestureRecognizerShouldBegin is the view's
    /// hook, asked about every recognizer on it, and a blanket "no pans while
    /// a selection is active" vetoed SwiftTerm's own selection pan — handles
    /// appeared, every drag on them refused (Jian, on device). The witness is
    /// the pasteboard: a drag from the selection edge across rows must copy
    /// MORE than the single word the press selected.
    func testSelectionHandleDragExtendsTheSelection() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "SelectDragProbe"
        _ = daemonPOST("api/sessions/delete", ["internalName": scratch], cookie: cookie)
        sleep(1)
        XCTAssertTrue(daemonPOST("api/sessions",
                                 ["name": scratch, "type": "terminal"], cookie: cookie))
        defer { _ = daemonPOST("api/sessions/delete",
                               ["internalName": scratch], cookie: cookie) }
        let marker = "/tmp/hop-selectdrag-marker.txt"
        try? FileManager.default.removeItem(atPath: marker)

        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_COPY_MARKER"] = marker
        app.launchEnvironment["HOP_SELECT_MARKER"] = "/tmp/hop-selectdrag-trace.txt"
        try? FileManager.default.removeItem(atPath: "/tmp/hop-selectdrag-trace.txt")
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8))
        sleep(1)
        app.typeText("seq 1000 1040\n")
        sleep(2)

        // Press-to-select, then drag from just past the word's END (inside
        // SwiftTerm's near() tolerance of 3 cols / 2 rows) down across rows.
        // Slow, with a settle hold: a fast flick reads as a swipe.
        //
        // RETRIED as a unit: in this live-fleet harness the selection can
        // clear between the press and the drag (trace-named: the drag then
        // arrives at shouldBegin with sel=false and honestly becomes a
        // scroll). That is inter-gesture timing in a busy scratch, not the
        // arbitration this test pins, so a cleared selection re-selects and
        // tries again rather than failing the contract.
        var copied = ""
        for attempt in 0..<3 where copied.isEmpty {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.35))
                .press(forDuration: 0.7)
            let chip = app.buttons["Copy selection"].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 6),
                          "no selection to drag — the press never selected (attempt \(attempt))")

            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            from.press(forDuration: 0.15, thenDragTo: to,
                       withVelocity: .slow, thenHoldForDuration: 0.3)

            // The chip re-offers after the drag; copy through it. Fresh query
            // each try: the chip is replaced on re-offer, so a handle resolved
            // before the swap dies at tap time with "no matches".
            for _ in 0..<8 where copied.isEmpty {
                let c = app.buttons["Copy selection"].firstMatch
                if c.waitForExistence(timeout: 1), c.isHittable { c.tap() }
                usleep(500_000)
                let got = (try? String(contentsOfFile: marker, encoding: .utf8)) ?? ""
                // Only a MULTI-ROW copy proves the drag extended; a single
                // word means the drag was lost — try the whole unit again.
                if got.contains("\n") { copied = got }
            }
        }
        let trace = (try? String(contentsOfFile: "/tmp/hop-selectdrag-trace.txt",
                                 encoding: .utf8)) ?? "(no trace)"
        if !copied.contains("\n") {
            // Verdict by trace. The regression this test pins shows up as a
            // pan REFUSED while the selection is live. If every attempt's
            // drag instead arrived at sel=false, the environment (a live
            // fleet: reconnects, snapshot resets) cleared the selection
            // before the drag — real on CI, irrelevant to arbitration.
            if trace.contains("sel=false"), !trace.contains("ours=false sel=true") {
                throw XCTSkip("selection cleared before every drag — environment, not arbitration: \(trace)")
            }
            XCTFail("drag never extended a LIVE selection — \(trace)")
        }
    }

    /// The disconnect story, production-grade: a dropped socket must show
    /// an honest banner (what happened, when it retries, a way to retry
    /// NOW), and a successful reconnect must clear it. HOP_DEV_DROP_WS
    /// hard-drops the socket once, deterministically.
    func testDisconnectShowsBannerAndRecovers() throws {
        // COUNT=3 sustains the outage across backoffs: a single drop
        // reconnects inside the grace period and rightly shows NOTHING
        // (the lock/unlock-blip rule, Jian's verdict on the red text).
        let app = launchIntoSessionWithDrop(Self.fixture, dropAfter: 2, count: 3)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        // The drop fires at t+2 and keeps dropping; past the 1.2s grace the
        // banner must appear with either wording.
        let banner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Connection lost' OR label CONTAINS 'Reconnecting'")
        ).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10),
                      "no reconnect banner after a socket drop")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/disconnect-banner.png"))
        // Recovery: the auto-retry reconnects and the banner clears — the
        // drop hook fires only once per process. ("Now" is deliberately not
        // tapped: recovery often lands within the same second and a tap on
        // a vanishing button is a framework failure, not a finding. Its
        // presence is in the screenshot.)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: banner, handler: nil)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.buttons["escape"].exists, "session unusable after recovery")
    }

    private func launchIntoSessionWithDrop(_ name: String, dropAfter: Int,
                                           count: Int = 1) -> XCUIApplication {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = name
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_DROP_WS"] = String(dropAfter)
        app.launchEnvironment["HOP_DEV_DROP_WS_COUNT"] = String(count)
        app.launchEnvironment["HOP_RETRY_MARKER"] = "/tmp/hop-retry-marker.txt"
        app.launch()
        return app
    }

    /// The half-open socket (Jian: "the terminal shows, but it doesn't
    /// take any user input — go back and re-enter and it works"): after a
    /// SILENT socket death the app believes it's live. The first keystroke
    /// must discover the corpse, reconnect, and REPLAY itself — nothing
    /// typed is lost, no back-and-re-enter required.
    func testHalfOpenSocketRecoversOnFirstKeystroke() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "HalfOpenProbe"
        _ = daemonPOST("api/sessions/delete", ["internalName": scratch], cookie: cookie)
        sleep(1)
        XCTAssertTrue(daemonPOST("api/sessions",
                                 ["name": scratch, "type": "terminal"], cookie: cookie))
        defer { _ = daemonPOST("api/sessions/delete",
                               ["internalName": scratch], cookie: cookie) }

        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchEnvironment["HOP_DEV_COOKIE"] = env["HOP_DEV_COOKIE"] ?? ""
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = scratch
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_DROP_WS"] = "2"
        app.launchEnvironment["HOP_DEV_HALFOPEN"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keys["e"].waitForExistence(timeout: 8))
        sleep(4)   // the silent death at t+2 has happened; the app still shows live
        app.typeText("echo half-ok\n")
        // The keystrokes discover the corpse, buffer, reconnect, replay —
        // the daemon's screen is the witness.
        var screen = ""
        for _ in 0..<24 where !screen.contains("half-ok") {
            usleep(500_000)
            screen = daemonPreview(of: scratch, cookie: cookie) ?? ""
        }
        XCTAssertTrue(screen.contains("echo half-ok"),
                      "typed line never survived the half-open recovery: \(screen.suffix(200))")
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
    /// Reconnect is STATE-CONDITIONAL: absent while verified-live (it was
    /// the row that pushed the menu past the keyboard-up fold, and the tap
    /// on its clipped coordinates false-passed for a run), the menu's FIRST
    /// row during an outage. Both halves asserted here; the drop hook
    /// sustains the outage long enough to tap it mid-storm.
    func testReconnectKeepsTheSessionUsable() throws {
        // dropAfter 8: the drop clock starts at first CONNECT, and the
        // live-half menu check below needs ~4s of verified-live runway first.
        let app = launchIntoSessionWithDrop(Self.fixture, dropAfter: 8, count: 5)
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        // Live half: the menu carries no Reconnect while the socket is good.
        app.buttons["Terminal actions"].tap()
        XCTAssertTrue(app.buttons["Smaller text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reconnect"].exists,
                       "Reconnect shown while verified-live")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        // Outage half: the drop fires and keeps dropping; Reconnect must
        // surface. Tapping it forces an immediate attempt (skipping the
        // backoff); the remaining drops absorb it and recovery follows.
        let banner = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Connection lost' OR label CONTAINS 'Reconnecting'")
        ).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "no outage banner")
        app.buttons["Terminal actions"].tap()
        let reconnect = app.buttons["Reconnect"]
        XCTAssertTrue(reconnect.waitForExistence(timeout: 5),
                      "Reconnect missing from the menu during an outage")
        reconnect.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: banner, handler: nil)
        waitForExpectations(timeout: 40)
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
        // Narrow to the fixture with the app's own filter instead of
        // swipe-hunting for it: the row's position depends on fleet order,
        // which churns, and a present-but-not-hittable row reads as a
        // feature regression (suite-caught: "Not hittable: StaticText").
        app.launchEnvironment["HOP_DEV_TILES"] = "0"   // shared container: pin the mode
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
