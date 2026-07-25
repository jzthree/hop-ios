import XCTest
@testable import HopSpike

// Regression cover for the pure logic behind the UI. Every case here is one
// that was either wrong at some point or would be invisible until it shipped.
final class HopSpikeTests: XCTestCase {

    private func session(_ json: [String: Any], seen: [String: Int] = [:]) -> HopSession {
        HopSession(json: json, seenBellSeq: seen)!
    }

    // MARK: attention / seen markers

    func testAttentionNeedsAStoredBaseline() {
        // The bug that shipped: with no stored marker the fallback was the
        // CURRENT bellSeq, so a session never opened on this device could
        // never signal attention — no dot, no notification, ever.
        let unseen = session(["name": "a", "bellSeq": 5])
        XCTAssertFalse(unseen.attention, "first sight must be silent, not noisy")

        let rung = session(["name": "a", "bellSeq": 6], seen: ["a": 5])
        XCTAssertTrue(rung.attention, "a bell past the baseline must raise attention")

        let quiet = session(["name": "a", "bellSeq": 5], seen: ["a": 5])
        XCTAssertFalse(quiet.attention)
    }

    // MARK: preview extraction

    func testPreviewSkipsTUIChrome() {
        // A naive tail showed every claude session as identical box-drawing.
        let screen = """
        Ran 2 shell commands
        002.slide.html was rebuilt at 22:37
        ╭──────────────────────────────────────╮
        │ ❯                                    │
        ╰──────────────────────────────────────╯
          ⏵⏵ bypass permissions on (shift+tab to cycle)
        """
        let tail = AppModel.meaningfulTail(of: screen, lines: 3)
        XCTAssertTrue(tail.contains("Ran 2 shell commands"))
        XCTAssertTrue(tail.contains("002.slide.html"))
        XCTAssertFalse(tail.contains("bypass permissions"))
        XCTAssertFalse(tail.contains("╭"))
        XCTAssertFalse(tail.contains("❯"))
    }

    func testPreviewKeepsOnlyTheRequestedNumberOfLines() {
        let screen = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let tail = AppModel.meaningfulTail(of: screen, lines: 3)
        XCTAssertEqual(tail.split(separator: "\n").count, 3)
        XCTAssertTrue(tail.contains("line 10"), "must keep the newest lines")
        XCTAssertFalse(tail.contains("line 7"))
    }

    // MARK: row metadata

    func testForegroundProcessVersionRendersAsClaude() {
        // claude retitles its process to a bare version ("2.1.220"), which is
        // meaningless as a badge.
        XCTAssertEqual(session(["name": "s", "foregroundProcess": "2.1.220"]).runningApp, "claude")
        XCTAssertEqual(session(["name": "s", "foregroundProcess": "vim"]).runningApp, "vim")
        XCTAssertEqual(session(["name": "s", "foregroundProcess": "zsh"]).runningApp, "",
                       "a plain shell is not worth a badge")
    }

    func testRelativeTimeAssumesMillisecondsAndSurvivesClockSkew() {
        // lastActivityAt is epoch MILLISECONDS. If hop ever sent seconds, every
        // row would read "56y" and nothing would fail loudly — so pin it.
        let nowMs = Date().timeIntervalSince1970 * 1000
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs]).relativeTime, "now")
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs - 30_000]).relativeTime, "30s")
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs - 5 * 60_000]).relativeTime, "5m")
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs - 3 * 3_600_000]).relativeTime, "3h")
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs - 2 * 86_400_000]).relativeTime, "2d")
        // A host clock slightly ahead of the phone gives a negative age; it
        // must read "now", never "-4s".
        XCTAssertEqual(session(["name": "s", "lastActivityAt": nowMs + 4_000]).relativeTime, "now")
        XCTAssertEqual(session(["name": "s"]).relativeTime, "", "never seen: no time at all")
    }

    func testHomeDirectoryShortensToTilde() {
        XCTAssertEqual(session(["name": "s", "cwd": "/Users/jianzhou/Code/hop2"]).shortCwd, "~/Code/hop2")
        XCTAssertEqual(session(["name": "s", "cwd": "/etc"]).shortCwd, "/etc")
    }

    // MARK: scope + filter

    func testScopeSplitsUserAndAgentSessions() {
        let list = [
            session(["name": "mine", "createdBy": "user"]),
            session(["name": "worker", "createdBy": "agent"]),
            session(["name": "legacy"])   // no createdBy => user side
        ]
        XCTAssertEqual(filterSessions(list, scope: .user, query: "").map(\.name), ["mine", "legacy"])
        XCTAssertEqual(filterSessions(list, scope: .agent, query: "").map(\.name), ["worker"])
        XCTAssertEqual(filterSessions(list, scope: .all, query: "").count, 3)
    }

    func testFilterMatchesNameCwdProcessAndTagline() {
        let list = [
            session(["name": "alpha", "cwd": "/Users/j/Code/hop2"]),
            session(["name": "beta", "foregroundProcess": "vim"]),
            session(["name": "gamma", "tagline": "Polish mobile client"])
        ]
        XCTAssertEqual(filterSessions(list, scope: .all, query: "hop2").map(\.name), ["alpha"])
        XCTAssertEqual(filterSessions(list, scope: .all, query: "vim").map(\.name), ["beta"])
        XCTAssertEqual(filterSessions(list, scope: .all, query: "mobile").map(\.name), ["gamma"])
        XCTAssertEqual(filterSessions(list, scope: .all, query: "  ").count, 3, "blank query filters nothing")
    }

    @MainActor
    func testServerURLNormalization() {
        // AppModel.serverURL is @AppStorage-backed and the test host IS the
        // app, so mutating it leaked into the installed app's real settings
        // (a test run left the app pointed at 127.0.0.1:8080). Restore it.
        let original = UserDefaults.standard.string(forKey: "serverURL")
        defer {
            if let original { UserDefaults.standard.set(original, forKey: "serverURL") }
            else { UserDefaults.standard.removeObject(forKey: "serverURL") }
        }
        let m = AppModel()
        m.serverURL = "hop.zhoulab.io"
        XCTAssertEqual(m.normalizedServerURL, "https://hop.zhoulab.io", "bare host gets https")
        XCTAssertEqual(m.wsBase, "wss://hop.zhoulab.io")

        m.serverURL = "https://hop.zhoulab.io/"
        XCTAssertEqual(m.normalizedServerURL, "https://hop.zhoulab.io", "trailing slash dropped")

        m.serverURL = "  http://127.0.0.1:8080  "
        XCTAssertEqual(m.normalizedServerURL, "http://127.0.0.1:8080", "explicit scheme kept")
        XCTAssertEqual(m.wsBase, "ws://127.0.0.1:8080")
    }

    func testNumericFieldsSurviveIntOrDoubleJSON() {
        // as? Double on an Int (or as? Int on a Double) silently yields nil,
        // which would zero activity time and bell counts with no error.
        let asInt = session(["name": "a", "lastActivityAt": 1_700_000_000, "bellSeq": 3])
        let asDouble = session(["name": "b", "lastActivityAt": 1_700_000_000.0, "bellSeq": 3.0])
        XCTAssertEqual(asInt.lastActivityAt, 1_700_000_000)
        XCTAssertEqual(asDouble.lastActivityAt, 1_700_000_000)
        XCTAssertEqual(asInt.bellSeq, 3)
        XCTAssertEqual(asDouble.bellSeq, 3)
    }

    func testProjectGroupingBucketsByWorkdir() {
        XCTAssertEqual(projectKey("/Users/jianzhou/Code/hop2/hay/apps"), "~/Code/hop2")
        XCTAssertEqual(projectKey("/Users/jianzhou"), "~")
        XCTAssertEqual(projectKey("/opt/data/things/deep"), "/opt/data/things")
        XCTAssertEqual(projectKey(nil), "Other")

        let list = [
            session(["name": "a", "cwd": "/Users/j/Code/hop2", "lastActivityAt": 900]),
            session(["name": "b", "cwd": "/Users/j/Code/hop2/hay", "lastActivityAt": 500]),
            session(["name": "c", "cwd": "/Users/j/Notes", "lastActivityAt": 950])
        ]
        let groups = groupSessionsByProject(list)
        XCTAssertEqual(groups.first?.label, "~/Notes", "most recent bucket leads")
        let hop2 = groups.first { $0.label == "~/Code/hop2" }
        XCTAssertEqual(hop2?.rows.map(\.name).sorted(), ["a", "b"], "root and subdir share a bucket")
    }

    func testOnlyNavigationKeysRepeatWhenHeld() {
        // A stuck ^C or a repeating paste is destructive; a repeating modifier
        // would just flap its armed state.
        for key in [AccessoryKey.up, .down, .left, .right, .pageUp, .pageDown] {
            XCTAssertTrue(key.repeats)
        }
        for key in [AccessoryKey.ctrlC, .paste, .ctrl, .alt, .esc, .tab, .dismiss, .tilde] {
            XCTAssertFalse(key.repeats)
        }
    }

    func testKeysWithoutAStaticSequenceAreHandledByTheView() {
        // ctrl/alt arm locally and dismiss is pure UI. paste belongs here too:
        // it must go through SwiftTerm so bracketed-paste markers are added
        // when the app asked for them — sending the clipboard raw made every
        // newline in a multi-line paste execute a line.
        for key in [AccessoryKey.ctrl, .alt, .dismiss, .paste] {
            XCTAssertNil(key.sequence)
        }
    }

    // MARK: links on screen

    func testLinkExtractionHandlesProsePunctuation() {
        let screen = """
        opened https://github.com/jzthree/hop/pull/12.
        preview at (http://localhost:5173) — try it
        docs: https://example.com/a_(b)_c
        """
        let links = extractLinks(from: screen)
        XCTAssertTrue(links.contains("https://github.com/jzthree/hop/pull/12"),
                      "a sentence period is not part of the URL")
        XCTAssertTrue(links.contains("http://localhost:5173"),
                      "a wrapping paren is not part of the URL")
        XCTAssertTrue(links.contains("https://example.com/a_(b)_c"),
                      "a balanced paren IS part of the URL")
    }

    func testLinkExtractionAddsSchemeAndOrdersNewestFirst() {
        let links = extractLinks(from: "server on localhost:3000\nthen https://later.example")
        XCTAssertEqual(links.first, "https://later.example", "the bottom of the screen is what you saw last")
        XCTAssertEqual(links.last, "http://localhost:3000", "a bare host:port still opens")
    }

    func testLinkExtractionDedupesAndIgnoresBareSchemes() {
        let links = extractLinks(from: "https://a.example\nhttp://\nhttps://a.example")
        XCTAssertEqual(links, ["https://a.example"])
    }

    func testWrappedRowsRejoinBeforeExtraction() {
        // A terminal wraps without a newline, so a long URL arrives split.
        let rows = [(text: "see https://example.com/very/long/", wrapped: false),
                    (text: "path/to/thing", wrapped: true),
                    (text: "done", wrapped: false)]
        XCTAssertEqual(extractLinks(from: screenText(rows: rows)),
                       ["https://example.com/very/long/path/to/thing"])
        XCTAssertEqual(extractLinks(from: rows.map(\.text).joined(separator: "\n")).first,
                       "https://example.com/very/long/", "naive join proves the wrap handling matters")
    }

    func testTUIBorderNeverJoinsTheLink() {
        // Rejoining a wrapped row can butt the URL against a box-drawing
        // border; "not whitespace" would swallow it into the link.
        let rows = [(text: "│ https://example.com/x", wrapped: false),
                    (text: "│", wrapped: true)]
        XCTAssertEqual(extractLinks(from: screenText(rows: rows)), ["https://example.com/x"])
    }

    // MARK: input buffered through an outage

    func testBufferedInputReplaysInOrderWithinTheAgeWindow() {
        let t0 = Date()
        var buf = PendingInput()
        buf.append("ls ", at: t0)
        buf.append("-la\n", at: t0.addingTimeInterval(1))
        let (replay, dropped) = buf.drain(now: t0.addingTimeInterval(2))
        XCTAssertEqual(replay, "ls -la\n", "order matters: it's a command line")
        XCTAssertEqual(dropped, 0)
        XCTAssertTrue(buf.isEmpty, "draining must not leave a double-send behind")
    }

    func testStaleBufferedInputIsDiscardedNotReplayed() {
        // The whole point of the age cap: a command typed a minute before the
        // reconnect must never land mid-something-else.
        let t0 = Date()
        var buf = PendingInput()
        buf.append("rm -rf old\n", at: t0)
        buf.append("echo hi\n", at: t0.addingTimeInterval(PendingInput.maxAge + 10))
        let (replay, dropped) = buf.drain(now: t0.addingTimeInterval(PendingInput.maxAge + 11))
        XCTAssertEqual(replay, "echo hi\n")
        XCTAssertEqual(dropped, 1)
    }

    func testBufferIsBoundedAndKeepsTheNewest() {
        let t0 = Date()
        var buf = PendingInput()
        for i in 0..<(PendingInput.maxEntries + 5) { buf.append("\(i % 10)", at: t0) }
        let (replay, _) = buf.drain(now: t0)
        XCTAssertEqual(replay.count, PendingInput.maxEntries, "a long outage must not grow without bound")
    }

    func testAccessoryKeysCarryTheRightEscapeSequences() {
        XCTAssertEqual(AccessoryKey.esc.sequence, "\u{1b}")
        XCTAssertEqual(AccessoryKey.tab.sequence, "\t")
        XCTAssertEqual(AccessoryKey.shiftTab.sequence, "\u{1b}[Z", "CSI Z is back-tab")
        XCTAssertEqual(AccessoryKey.ctrlC.sequence, "\u{03}")
        XCTAssertEqual(AccessoryKey.up.sequence, "\u{1b}[A")
        XCTAssertEqual(AccessoryKey.down.sequence, "\u{1b}[B")
        XCTAssertEqual(AccessoryKey.right.sequence, "\u{1b}[C")
        XCTAssertEqual(AccessoryKey.left.sequence, "\u{1b}[D")
        XCTAssertEqual(AccessoryKey.pageUp.sequence, "\u{1b}[5~")
        XCTAssertEqual(AccessoryKey.pageDown.sequence, "\u{1b}[6~")
        XCTAssertNil(AccessoryKey.ctrl.sequence, "modifiers arm locally")
        XCTAssertNil(AccessoryKey.dismiss.sequence)
    }

    func testPollingBacksOffOnCellularAndStopsPreviewsInLowDataMode() {
        XCTAssertEqual(pollInterval(expensive: false, constrained: false), 5, "Wi-Fi keeps attention immediate")
        XCTAssertGreaterThan(pollInterval(expensive: true, constrained: false), 5, "cellular costs the user money")
        XCTAssertGreaterThan(pollInterval(expensive: true, constrained: true),
                             pollInterval(expensive: true, constrained: false),
                             "Low Data Mode is an explicit instruction, not a hint")
        XCTAssertNotNil(previewInterval(expensive: true, constrained: false))
        XCTAssertNil(previewInterval(expensive: false, constrained: true),
                     "previews are a nicety and cost a render each — drop them in Low Data Mode")
    }

    func testRowSummaryLeadsWithWhatMatters() {
        // VoiceOver reads one utterance per row; attention has to come early,
        // and the raw terminal preview must not be in it at all.
        let s = session(["name": "Orion", "tagline": "Polish mobile client",
                         "foregroundProcess": "vim", "bellSeq": 4], seen: ["Orion": 3])
        let spoken = SessionRow(session: s, preview: "╭───╮\n│ ❯ │").spokenSummary
        XCTAssertTrue(spoken.hasPrefix("Orion, wants attention"), "got: \(spoken)")
        XCTAssertTrue(spoken.contains("Polish mobile client"))
        XCTAssertFalse(spoken.contains("╭"), "scrollback is a glance aid, not something to listen to")
    }

    // MARK: find in scrollback

    func testFindStepsToEarlierMatchesInsteadOfRepeatingTheNewest() {
        // The bug: search always restarted at the live edge, so "find again"
        // returned the same row forever and an earlier occurrence — the one
        // you're usually hunting — was unreachable.
        let rows = ["error: first", "ok", "error: second", "ok", "tail"]
        let line: (Int) -> String? = { $0 >= 0 && $0 < rows.count ? rows[$0] : nil }
        let newest = findMatchRow(from: rows.count, direction: -1, needle: "error", line: line)
        XCTAssertEqual(newest, 2)
        let earlier = findMatchRow(from: newest!, direction: -1, needle: "error", line: line)
        XCTAssertEqual(earlier, 0, "stepping up must reach the older match")
        XCTAssertNil(findMatchRow(from: earlier!, direction: -1, needle: "error", line: line),
                     "and then honestly run out")
    }

    func testFindWalksForwardAndStopsAtTheLiveEdge() {
        let rows = ["error: first", "ok", "error: second"]
        let line: (Int) -> String? = { $0 >= 0 && $0 < rows.count ? rows[$0] : nil }
        XCTAssertEqual(findMatchRow(from: 0, direction: 1, needle: "error", line: line), 2)
        XCTAssertNil(findMatchRow(from: 2, direction: 1, needle: "error", line: line),
                     "past the live edge is the end, not a wrap")
    }

    func testFindIsCaseInsensitiveAndIgnoresEmptyQueries() {
        let line: (Int) -> String? = { $0 == 3 ? "Fatal: BOOM" : "quiet" }
        XCTAssertEqual(findMatchRow(from: 9, direction: -1, needle: "fatal", line: line), 3)
        XCTAssertNil(findMatchRow(from: 9, direction: -1, needle: "", line: line))
    }

    func testTheSessionYouAreWatchingNeverAlertsYou() {
        // A banner over the terminal you're reading, for that terminal, is
        // noise — and it inflates the badge for something already seen.
        let list = [
            session(["name": "watching", "bellSeq": 7], seen: ["watching": 6]),
            session(["name": "elsewhere", "bellSeq": 3], seen: ["elsewhere": 2])
        ]
        XCTAssertEqual(list.filter(\.attention).count, 2, "both want attention")
        XCTAssertEqual(alertable(list, openSession: "watching").map(\.name), ["elsewhere"])
        XCTAssertEqual(alertable(list, openSession: nil).count, 2, "in the list, both still count")

        // A port forward has no terminal and cannot ring; counting one would
        // inflate a badge with nothing behind it to clear.
        let withPort = list + [session(["name": "web", "type": "port", "bellSeq": 9],
                                       seen: ["web": 0])]
        XCTAssertEqual(alertable(withPort, openSession: nil).count, 2, "ports never alert")
    }

    func testAuthenticatorCodeIsCleanedAndBounded() {
        XCTAssertEqual(sanitizedCode("123 456"), "123456", "authenticators copy a space in")
        XCTAssertEqual(sanitizedCode("123-456"), "123456")
        XCTAssertEqual(sanitizedCode("1234567890"), "123456", "six digits, not the whole paste")
        XCTAssertEqual(sanitizedCode("abc"), "", "a number pad can still receive a paste")
    }

    func testMarkerRebaselinesWhenASessionIsRecreated() {
        // Never seen: silent baseline, so history isn't a pile of unread bells.
        XCTAssertEqual(rebaselinedMarker(existing: nil, bellSeq: 7), 7)
        // Normal progress: leave the marker alone so the bell still counts.
        XCTAssertNil(rebaselinedMarker(existing: 7, bellSeq: 9))
        XCTAssertNil(rebaselinedMarker(existing: 7, bellSeq: 7))
        // Counter went backwards — killed and recreated under the same name.
        // Without this, the new session stays silent until it out-rings the
        // one it replaced.
        XCTAssertEqual(rebaselinedMarker(existing: 50, bellSeq: 0), 0)
        XCTAssertEqual(rebaselinedMarker(existing: 50, bellSeq: 1), 1)
    }

    func testPortSessionsNeverAppear() {
        let list = [session(["name": "web", "type": "port"]), session(["name": "shell"])]
        XCTAssertEqual(filterSessions(list, scope: .all, query: "").map(\.name), ["shell"])
    }

    // MARK: - Whether the remote app takes wheel events

    func testWheelNeedsBothTrackingAndSgr() {
        var m = RemoteMouseState()
        XCTAssertFalse(m.takesWheel)                 // a plain shell: neither
        m.seed(reporting: true, sgr: false)
        // Tracking without SGR means the app expects the legacy encoding,
        // which caps coordinates at 223 and is not what we send.
        XCTAssertFalse(m.takesWheel)
        m.seed(reporting: true, sgr: true)
        XCTAssertTrue(m.takesWheel)                  // claude, as measured
    }

    func testModesFollowTheAppMidSession() {
        var m = RemoteMouseState()
        // claude starting inside a shell session we're already watching.
        m.note("\u{1b}[?1003h\u{1b}[?1006h")
        XCTAssertTrue(m.takesWheel)
        // ...and exiting, handing the screen back. A stale "on" here would
        // send wheel events at a bash prompt, which arrive as junk input.
        m.note("\u{1b}[?1003l\u{1b}[?1006l")
        XCTAssertFalse(m.takesWheel)
    }

    func testCombinedAndSplitModeSequences() {
        var m = RemoteMouseState()
        m.note("\u{1b}[?1000;1006h")                  // one sequence, both params
        XCTAssertTrue(m.takesWheel)

        // A mode set can arrive split across two WebSocket messages; without
        // the carry-over the app looks like it never asked for anything.
        var split = RemoteMouseState()
        split.note("output\u{1b}[?10")
        split.note("03h\u{1b}[?1006h")
        XCTAssertTrue(split.takesWheel)
    }

    func testUnrelatedModesAreIgnored() {
        var m = RemoteMouseState()
        m.seed(reporting: true, sgr: true)
        m.note("\u{1b}[?1049h\u{1b}[?25l\u{1b}[?2004h")  // alt screen, cursor, paste
        XCTAssertTrue(m.takesWheel)
    }

    // MARK: - The wheel events themselves

    func testWheelDirectionAndAim() {
        // Dragging DOWN reveals older output, which is wheel UP (64).
        XCTAssertEqual(wheelSequence(rows: 1, cols: 80, screenRows: 24),
                       "\u{1b}[<64;40;12M")
        XCTAssertEqual(wheelSequence(rows: -1, cols: 80, screenRows: 24),
                       "\u{1b}[<65;40;12M")
        // One notch per row of travel, and no events for no travel.
        XCTAssertEqual(wheelSequence(rows: 3, cols: 80, screenRows: 24).count,
                       "\u{1b}[<64;40;12M".count * 3)
        XCTAssertEqual(wheelSequence(rows: 0, cols: 80, screenRows: 24), "")
    }

    func testWheelIsCappedAndNeverAimsAtRowZero() {
        // A fling isn't a thousand notches the app has to chew through.
        let seq = wheelSequence(rows: 500, cols: 80, screenRows: 24, cap: 40)
        XCTAssertEqual(seq.components(separatedBy: "M").count - 1, 40)
        // Coordinates are 1-based: a tiny terminal must not report row 0.
        XCTAssertEqual(wheelSequence(rows: 1, cols: 1, screenRows: 1), "\u{1b}[<64;1;1M")
    }

    // MARK: - The coast after a flick

    func testOnlyAFlickCoasts() {
        var m = ScrollMomentum()
        // Letting go of a slow, careful drag should stop where you left it.
        XCTAssertFalse(m.start(pointsPerSecond: 40))
        XCTAssertNil(m.step(elapsed: 1.0 / 60))
        XCTAssertTrue(m.start(pointsPerSecond: 900))
        XCTAssertNotNil(m.step(elapsed: 1.0 / 60))
    }

    func testCoastDecaysAndEnds() {
        var m = ScrollMomentum()
        _ = m.start(pointsPerSecond: 1200)
        var seconds = 0.0
        var last = Double.infinity
        while let step = m.step(elapsed: 1.0 / 60) {
            XCTAssertLessThan(abs(step), abs(last), "coast must slow every frame")
            last = step
            seconds += 1.0 / 60
            XCTAssertLessThan(seconds, 30, "coast never ended")
        }
        // A couple of seconds — long enough to feel like inertia, short enough
        // that the screen isn't still moving when you look up.
        XCTAssertGreaterThan(seconds, 1.0)
        XCTAssertLessThan(seconds, 3.0)
    }

    /// The one that matters on real hardware. CADisplayLink runs at 120Hz on a
    /// ProMotion phone and 60Hz in the simulator, so a coast that decays per
    /// FRAME is twice as fast and half as long on the device — while every
    /// test and every simulator run says it's fine.
    func testCoastIsTheSameAtAnyRefreshRate() {
        func run(fps: Double) -> (distance: Double, seconds: Double) {
            var m = ScrollMomentum()
            _ = m.start(pointsPerSecond: 1500)
            var distance = 0.0, seconds = 0.0
            while let step = m.step(elapsed: 1 / fps) {
                distance += step
                seconds += 1 / fps
            }
            return (distance, seconds)
        }
        let sixty = run(fps: 60), oneTwenty = run(fps: 120)
        XCTAssertEqual(sixty.distance, oneTwenty.distance, accuracy: 10)
        XCTAssertEqual(sixty.seconds, oneTwenty.seconds, accuracy: 0.05)
    }

    func testCoastDistanceStaysWithinAFewScreenfuls() {
        // A hard flick on a phone is roughly 2000 pt/s. The coast that follows
        // should be measured in screens, not in thousands of lines: this is
        // sent to the remote app as wheel notches, and there is no taking it
        // back once it's gone.
        let hard = ScrollMomentum.coastDistance(pointsPerSecond: 2000)
        XCTAssertGreaterThan(hard, 400)              // more than one screen
        XCTAssertLessThan(hard, 1600)                // fewer than ~2 screens
        XCTAssertEqual(ScrollMomentum.coastDistance(pointsPerSecond: 10), 0)
        // Direction is preserved: flicking up coasts up.
        XCTAssertLessThan(ScrollMomentum.coastDistance(pointsPerSecond: -2000), 0)
        // And the closed form agrees with actually stepping it.
        var m = ScrollMomentum()
        _ = m.start(pointsPerSecond: 2000)
        var stepped = 0.0
        while let step = m.step(elapsed: 1.0 / 60) { stepped += step }
        XCTAssertEqual(stepped, hard, accuracy: hard * 0.05)
    }
}
