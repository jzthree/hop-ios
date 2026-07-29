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
        var m = RemoteModes()
        XCTAssertFalse(m.takesWheel)                 // a plain shell: neither
        m.seed(altScreen: true, mouseReporting: true, mouseSgr: false)
        // Tracking without SGR means the app expects the legacy encoding,
        // which caps coordinates at 223 and is not what we send.
        XCTAssertFalse(m.takesWheel)
        m.seed(altScreen: true, mouseReporting: true, mouseSgr: true)
        XCTAssertTrue(m.takesWheel)                  // claude, as measured
    }

    func testModesFollowTheAppMidSession() {
        var m = RemoteModes()
        // claude starting inside a shell session we're already watching.
        m.note("\u{1b}[?1003h\u{1b}[?1006h")
        XCTAssertTrue(m.takesWheel)
        // ...and exiting, handing the screen back. A stale "on" here would
        // send wheel events at a bash prompt, which arrive as junk input.
        m.note("\u{1b}[?1003l\u{1b}[?1006l")
        XCTAssertFalse(m.takesWheel)
    }

    func testCombinedAndSplitModeSequences() {
        var m = RemoteModes()
        m.note("\u{1b}[?1000;1006h")                  // one sequence, both params
        XCTAssertTrue(m.takesWheel)

        // A mode set can arrive split across two WebSocket messages; without
        // the carry-over the app looks like it never asked for anything.
        var split = RemoteModes()
        split.note("output\u{1b}[?10")
        split.note("03h\u{1b}[?1006h")
        XCTAssertTrue(split.takesWheel)
    }

    func testUnrelatedModesAreIgnored() {
        var m = RemoteModes()
        m.seed(altScreen: true, mouseReporting: true, mouseSgr: true)
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

    // MARK: - Which sink a drag goes to

    func testAFreshShellPromptNeverGetsPageKeys() {
        // The bug this pins: deciding by "do we have scrollback yet" fires
        // Page keys at a bare shell that never asked for them, and then
        // silently switches to scrolling our own buffer once enough output has
        // piled up — the same gesture doing two different things on the same
        // session depending on how long you'd been looking at it.
        XCTAssertEqual(scrollSink(altScreen: false, takesWheel: false), .viewport)
        XCTAssertEqual(scrollSink(altScreen: false, takesWheel: true), .viewport)
        // The app owns the screen: it scrolls, we don't.
        XCTAssertEqual(scrollSink(altScreen: true, takesWheel: true), .wheel)
        XCTAssertEqual(scrollSink(altScreen: true, takesWheel: false), .pageKeys)
    }

    func testAltScreenFollowsTheApp() {
        var m = RemoteModes()
        XCTAssertFalse(m.altScreen)
        m.note("\u{1b}[?1049h")                        // claude starts
        XCTAssertTrue(m.altScreen)
        m.note("\u{1b}[?1049l")                        // ...and exits
        XCTAssertFalse(m.altScreen)
        // The older spellings of the same thing.
        m.note("\u{1b}[?47h")
        XCTAssertTrue(m.altScreen)
        m.note("\u{1b}[?1047l")
        XCTAssertFalse(m.altScreen)
    }

    func testScrollSpeedUsesTheROWSWEDRAW() {
        // hop runs ONE PTY at one size for everyone, so this phone's terminal
        // is often sized by a desktop peer. Dividing the view height by the
        // terminal's row count then makes every row of finger travel count as
        // two, and scrolling runs at double speed for as long as the desktop
        // holds the size.
        let phone = drawnCellHeight(viewHeight: 460, drawnRows: 23, terminalRows: 50)
        XCTAssertEqual(phone, 20, accuracy: 0.01)
        // Before the first layout there is nothing better than the terminal.
        XCTAssertEqual(drawnCellHeight(viewHeight: 460, drawnRows: 0, terminalRows: 23),
                       20, accuracy: 0.01)
        // Degenerate sizes must not divide by zero or return zero: a zero cell
        // turns one point of travel into an infinite number of rows.
        XCTAssertEqual(drawnCellHeight(viewHeight: 0, drawnRows: 0, terminalRows: 0), 1)
        XCTAssertGreaterThan(drawnCellHeight(viewHeight: 10, drawnRows: 1000, terminalRows: 0), 0)
    }

    func testOneBellIsOneNotification() {
        XCTAssertTrue(shouldNotify(bellSeq: 3, lastNotified: nil))    // never posted
        XCTAssertFalse(shouldNotify(bellSeq: 3, lastNotified: 3))     // already posted
        XCTAssertTrue(shouldNotify(bellSeq: 4, lastNotified: 3))      // rang again
        // Killed and recreated under the same name: the counter restarts, and
        // the predecessor's record must not silence the new session.
        XCTAssertTrue(shouldNotify(bellSeq: 1, lastNotified: 50))
        XCTAssertTrue(shouldNotify(bellSeq: 0, lastNotified: 50))
    }

    // MARK: - Parked sessions

    func testParkedSessionsAreHiddenFromBrowsingButStillSearchable() {
        let list = [session(["name": "Orion"]),
                    session(["name": "Umbra", "parked": true])]
        // Browsing: parking is what the user did to stop seeing it. A session
        // parked from the desk that still fills your pocket is not parked.
        XCTAssertEqual(filterSessions(list, scope: .all, query: "").map(\.name), ["Orion"])
        // Searching: parked is "not my working set", not "gone" — and hiding a
        // session you explicitly typed the name of just looks broken. Same rule
        // as hop's own switcher.
        XCTAssertEqual(filterSessions(list, scope: .all, query: "umb").map(\.name), ["Umbra"])
    }

    func testParkedSessionsDoNotRingThePhone() {
        let ringing = session(["name": "Umbra", "bellSeq": 5, "parked": true])
        let alsoRinging = session(["name": "Orion", "bellSeq": 5])
        let seen = ["Umbra": 0, "Orion": 0]
        let list = [HopSession(json: ["name": "Umbra", "bellSeq": 5, "parked": true],
                               seenBellSeq: seen)!,
                    HopSession(json: ["name": "Orion", "bellSeq": 5], seenBellSeq: seen)!]
        XCTAssertTrue(list[0].attention, "the parked one IS ringing")
        // ...but a notification from something deliberately hidden, which then
        // isn't in the list you open to find it, is the worst of both.
        XCTAssertEqual(alertable(list, openSession: nil).map(\.name), ["Orion"])
        _ = (ringing, alsoRinging)
    }

    func testArchivedIsParkedAndStopped() {
        // Archived sessions are parked too (the daemon sets both), so they
        // follow the same hiding rule; `archived` only says that opening one
        // resumes a stopped process rather than attaching to a running one.
        let s = session(["name": "Titan", "parked": true, "archived": true])
        XCTAssertTrue(s.parked)
        XCTAssertTrue(s.archived)
        XCTAssertFalse(session(["name": "Titan"]).archived)
    }

    func testJSONNumbersSurviveEitherForm() {
        // The hazard these helpers exist for: JSONSerialization hands back
        // NSNumber, and a straight cast to the WRONG one of Int/Double yields
        // nil — silently, so the value just becomes a default.
        XCTAssertEqual(jsonInt(NSNumber(value: 51)), 51)
        XCTAssertEqual(jsonInt(NSNumber(value: 51.0)), 51)
        XCTAssertEqual(jsonInt(Double(51)), 51)
        XCTAssertEqual(jsonInt(Int(51)), 51)
        XCTAssertNil(jsonInt("51"))          // a string is not a number
        XCTAssertNil(jsonInt(nil))

        XCTAssertEqual(jsonDouble(NSNumber(value: 12)), 12)
        XCTAssertEqual(jsonDouble(Int(12)), 12)
        XCTAssertEqual(jsonDouble(12.5), 12.5)
        XCTAssertNil(jsonDouble("12.5"))
    }

    func testBellSeqFromAPushSurvives() {
        // The APNs case specifically: a bell counter decoded from a push
        // arrives as NSNumber, and losing it means marking the session seen at
        // 0 — so answering a notification would leave the dot and the badge
        // exactly where they were.
        let fromPush: [String: Any] = ["session": "Orion", "bellSeq": NSNumber(value: 42)]
        XCTAssertEqual(jsonInt(fromPush["bellSeq"]), 42)
    }

    func testNotificationBodySkipsThePromptNotTheMessage() {
        // The measured case: printf output, then the prompt returns. The body
        // must be what the session SAID, not where it said it.
        XCTAssertEqual(notificationLine(from:
            "answer me \njianzhou@MED-GEN-ML-15 hop2 %"), "answer me")
        // A claude question is the last line and must survive untouched.
        XCTAssertEqual(notificationLine(from:
            "2. Resume full session\nEnter to confirm · Esc to cancel"),
            "Enter to confirm · Esc to cancel")
        // "CPU 97%" ends in % but is not a prompt — no user@host shape.
        XCTAssertEqual(notificationLine(from: "build ok\nCPU 97%"), "CPU 97%")
        // A bare composer line is a prompt.
        XCTAssertEqual(notificationLine(from: "done here\n❯"), "done here")
        // All prompts: better a prompt than an empty notification.
        XCTAssertEqual(notificationLine(from: "jian@host dir %"), "jian@host dir %")
        XCTAssertNil(notificationLine(from: "  \n a "))
    }

    func testSwitcherMenuMatchesTheParkedRules() {
        let seen: [String: Int] = [:]
        func mk(_ json: [String: Any]) -> HopSession { HopSession(json: json, seenBellSeq: seen)! }
        let sessions = [
            mk(["name": "here", "live": true]),
            mk(["name": "other", "live": true]),
            mk(["name": "napping", "live": true, "parked": true]),
            mk(["name": "web", "live": true, "type": "port"]),
            mk(["name": "dead", "live": false]),
        ]
        // Parked is "not my working set" — the same rule that hides it from
        // browsing and silences its bells. The switcher offering it anyway
        // made the rule mean different things in different places.
        XCTAssertEqual(switcherCandidates(sessions, excluding: "here").map(\.name),
                       ["other"])
        // The cap is a cap.
        let many = (0..<20).map { mk(["name": "s\($0)", "live": true]) }
        XCTAssertEqual(switcherCandidates(many, excluding: "none").count, 12)
    }

    func testFitFontSizeMapsColumnsToPoints() {
        // 12pt font, 7.2pt cells, 402pt view: 51 cols fit naturally. Fitting
        // 90 columns needs cells of 402/90 = 4.47pt → about 7.4pt type.
        let f = fitFontSize(base: 12, baseCellWidth: 7.2, viewWidth: 402, gridCols: 90)
        XCTAssertEqual(f, 12 * (402.0/90.0) / 7.2, accuracy: 0.01)
        // Never grows past the user's chosen size…
        XCTAssertEqual(fitFontSize(base: 12, baseCellWidth: 7.2, viewWidth: 402, gridCols: 40), 12)
        // …and never shrinks below the readability floor: 500 columns would
        // want sub-pixel glyphs, which is a texture, not text.
        XCTAssertEqual(fitFontSize(base: 12, baseCellWidth: 7.2, viewWidth: 402, gridCols: 500), 4)
        // Degenerate inputs change nothing.
        XCTAssertEqual(fitFontSize(base: 12, baseCellWidth: 0, viewWidth: 402, gridCols: 90), 12)
    }

    func testBackspaceRepeatsBecauseNothingElseCan() {
        XCTAssertEqual(AccessoryKey.backspace.sequence, "\u{7f}")
        // Removed once on the belief the system delete repeats on hardware.
        // It does not — the observation that retired this key was made on a
        // build where this key sat one row above the system delete. Hold-to-
        // delete vanished the release after. This test is the tombstone.
        XCTAssertTrue(AccessoryKey.backspace.repeats)
        XCTAssertFalse(AccessoryKey.ctrlC.repeats)
        XCTAssertFalse(AccessoryKey.paste.repeats)
    }

    // MARK: tile typography

    func testTileTypeScalesWhenItFitsLegibly() {
        // 40 columns across 174pt wants 174/40/0.6 = 7.25pt — above the floor,
        // so the whole screen renders untouched.
        let r = TileTypography.window(text: "a\nb\nc", cols: 40, width: 174, height: 160)
        XCTAssertEqual(r.text, "a\nb\nc")
        XCTAssertEqual(r.pt, 174.0 / 40.0 / 0.6, accuracy: 0.001)
    }

    func testTileTypeHoldsTheFloorAndWindowsTheBottom() {
        // 90 columns would need 3.2pt — illegible. The floor holds and the
        // tile shows the LAST rows that fit instead: 160pt / (7 × 1.19) = 19.
        let lines = (1...44).map { "row\($0)" }
        let r = TileTypography.window(text: lines.joined(separator: "\n"),
                                      cols: 90, width: 174, height: 160)
        XCTAssertEqual(r.pt, TileTypography.floorPt)
        let out = r.text.split(separator: "\n")
        XCTAssertEqual(out.count, 19)
        XCTAssertEqual(out.last, "row44")     // live edge kept, history dropped
        XCTAssertEqual(out.first, "row26")
    }

    func testBioLockLocksOnBackgroundOnly() {
        // .inactive fires for the app-switcher flash, permission alerts and
        // notification pulls — locking there is churn, not protection.
        XCTAssertTrue(BioLock.shouldLock(enabled: true, phase: .background))
        XCTAssertFalse(BioLock.shouldLock(enabled: true, phase: .inactive))
        XCTAssertFalse(BioLock.shouldLock(enabled: true, phase: .active))
        // Off means off, in every phase.
        XCTAssertFalse(BioLock.shouldLock(enabled: false, phase: .background))
    }

    func testClickSequenceIsPressAndRelease() {
        XCTAssertEqual(clickSequence(col: 12, row: 40),
                       "\u{1b}[<0;12;40M\u{1b}[<0;12;40m")
        XCTAssertEqual(clickSequence(col: 0, row: -3),
                       "\u{1b}[<0;1;1M\u{1b}[<0;1;1m", "clamped to the grid")
    }

    func testCtrlComboMasksLikeTheArmedPath() {
        XCTAssertEqual(AccessoryKey.ctrlCombo("a").sequence, "\u{01}")
        XCTAssertEqual(AccessoryKey.ctrlCombo("r").sequence, "\u{12}")
        XCTAssertEqual(AccessoryKey.ctrlCombo("l").sequence, "\u{0c}")
        XCTAssertEqual(AccessoryKey.ctrlCombo("z").sequence, "\u{1a}")
        XCTAssertEqual(AccessoryKey.ctrlCombo("C").sequence, "\u{03}",
                       "case-insensitive, same as holding shift at a real keyboard")
        XCTAssertNil(AccessoryKey.ctrlCombo("1").sequence, "non-letters send nothing")
        XCTAssertFalse(AccessoryKey.ctrlCombo("c").repeats, "a repeating ^C is destructive")
    }

    func testFleetStatusLineSpeaksLikeASentence() {
        XCTAssertEqual(fleetStatusLine(wanting: 0, total: 0), "No sessions running.")
        XCTAssertEqual(fleetStatusLine(wanting: 0, total: 1),
                       "1 session running, nothing waiting on you.")
        XCTAssertEqual(fleetStatusLine(wanting: 1, total: 19),
                       "19 sessions running, 1 wants you.")
        XCTAssertEqual(fleetStatusLine(wanting: 3, total: 19),
                       "19 sessions running, 3 want you.")
    }

    func testHandoffURLIsTheWebDeepLink() {
        XCTAssertEqual(handoffURL(server: "https://hop.zhoulab.io",
                                  internalName: "Meridian")?.absoluteString,
                       "https://hop.zhoulab.io?room=Meridian")
        // Session names are user text — the escaping is the point.
        XCTAssertEqual(handoffURL(server: "https://hop.zhoulab.io",
                                  internalName: "my session")?.absoluteString,
                       "https://hop.zhoulab.io?room=my%20session")
        // A schemeless or hostless server must produce nothing rather than a
        // relative URL Safari can't open (the cookie-seed wipeout's cousin).
        XCTAssertNil(handoffURL(server: "not a url", internalName: "x"))
        XCTAssertNil(handoffURL(server: "https://hop.zhoulab.io", internalName: ""))
    }

    func testCopyableScreenStripsThePadding() {
        // Grid padding: every line padded to cols, quiet tail is blank rows.
        XCTAssertEqual(copyableScreen("$ ls   \n a.txt  \n       \n       "),
                       "$ ls\n a.txt")
        // Leading whitespace is CONTENT (indentation); only trailing goes.
        XCTAssertEqual(copyableScreen("  indented   "), "  indented")
        // Interior blank lines survive — only the tail is padding.
        XCTAssertEqual(copyableScreen("a\n\nb\n\n"), "a\n\nb")
        // Nothing worth copying hides the menu item.
        XCTAssertNil(copyableScreen(nil))
        XCTAssertNil(copyableScreen("   \n   "))
    }

    func testFleetSummaryFullAndCompactAgreeOnTheFacts() {
        // Quiet fleet, everything visible.
        XCTAssertEqual(fleetSummaryLine(shown: 21, total: 21, wanting: 0,
                                        hiddenWanting: 0, parked: 0),
                       "21 sessions · nothing waiting on you")
        XCTAssertEqual(fleetSummaryCompact(shown: 21, total: 21, wanting: 0,
                                           hiddenWanting: 0, parked: 0),
                       "21 · quiet")
        // Filtered scope + parked note.
        XCTAssertEqual(fleetSummaryLine(shown: 18, total: 21, wanting: 0,
                                        hiddenWanting: 0, parked: 1),
                       "18 of 21 · nothing waiting on you · 1 parked")
        XCTAssertEqual(fleetSummaryCompact(shown: 18, total: 21, wanting: 0,
                                           hiddenWanting: 0, parked: 1),
                       "18/21 · quiet · 1 parked")
        // Attention, with one wanter outside the visible rows.
        XCTAssertEqual(fleetSummaryLine(shown: 18, total: 21, wanting: 2,
                                        hiddenWanting: 1, parked: 0),
                       "18 of 21 · 2 want you (1 not shown here)")
        XCTAssertEqual(fleetSummaryCompact(shown: 18, total: 21, wanting: 2,
                                           hiddenWanting: 1, parked: 0),
                       "18/21 · 2 want you (+1)")
        // Singular agreement survives compaction.
        XCTAssertEqual(fleetSummaryCompact(shown: 1, total: 1, wanting: 1,
                                           hiddenWanting: 0, parked: 0),
                       "1 · 1 wants you")
    }

    func testSpotlightEntriesShapeAndExclusions() {
        func s(_ name: String, tagline: String = "", cwd: String = "",
               port: Bool = false) -> HopSession {
            HopSession(json: ["internalName": name, "name": name, "live": true,
                              "type": port ? "port" : "terminal",
                              "tagline": tagline, "cwd": cwd], seenBellSeq: [:])!
        }
        let entries = spotlightEntries([
            s("Orion", tagline: "Improving the switcher"),
            s("bare", cwd: "/Users/x/Code/hop2"),
            s("prt", port: true),
        ])
        XCTAssertEqual(entries.map(\.id), ["Orion", "bare"], "ports never index")
        XCTAssertEqual(entries[0].description, "Improving the switcher")
        XCTAssertEqual(entries[1].description, projectKey("/Users/x/Code/hop2"),
                       "cwd stands in when there is no tagline")
    }

    func testScreenPreviewEqualityGatesTheStoreWrite() {
        let rows = TileInk.decode([[["t": "x", "f": "#ff0000"]]])
        let a = ScreenPreview(text: "same", cols: 80, rows: 24, colorRows: rows)
        let b = ScreenPreview(text: "same", cols: 80, rows: 24, colorRows: rows)
        XCTAssertEqual(a, b, "identical screens must compare equal, or the skip never fires")
        let c = ScreenPreview(text: "same", cols: 80, rows: 24,
                              colorRows: TileInk.decode([[["t": "x", "f": "#00ff00"]]]))
        XCTAssertNotEqual(a, c, "a colour-only change must still invalidate")
    }

    func testHighlightMatchesLightsEveryHitAndKeepsTheText() {
        let out = highlightMatches(in: "Error in hopper: hop failed", query: "hop")
        XCTAssertEqual(String(out.characters), "Error in hopper: hop failed",
                       "highlighting must never alter the text")
        // Two hits ("hopper", "hop"), each its own styled run.
        let styled = out.runs.filter { $0.foregroundColor != nil }.count
        XCTAssertEqual(styled, 2)
        // Case-insensitive, and an empty query styles nothing.
        XCTAssertEqual(highlightMatches(in: "HOP", query: "hop").runs
            .filter { $0.foregroundColor != nil }.count, 1)
        XCTAssertTrue(highlightMatches(in: "text", query: "  ").runs
            .allSatisfy { $0.foregroundColor == nil })
    }

    func testSessionBusyToleratesBothUnitsAndExpires() {
        let nowS = 1_785_226_000.0
        // Milliseconds (what the daemon actually sends) and seconds both work:
        // a unit isn't something to trust across a protocol boundary.
        XCTAssertTrue(sessionBusy(lastActivityAt: (nowS - 3) * 1000, now: nowS))
        XCTAssertTrue(sessionBusy(lastActivityAt: nowS - 3, now: nowS))
        // Quiet for longer than the window → not busy; zero → never busy.
        XCTAssertFalse(sessionBusy(lastActivityAt: (nowS - 30) * 1000, now: nowS))
        XCTAssertFalse(sessionBusy(lastActivityAt: 0, now: nowS))
    }

    func testRecentProjectsDedupesByProjectMostRecentFirst() {
        func s(_ name: String, cwd: String, at: Double, port: Bool = false) -> HopSession {
            HopSession(json: ["internalName": name, "name": name, "live": true,
                              "type": port ? "port" : "terminal",
                              "cwd": cwd, "lastActivityAt": at], seenBellSeq: [:])!
        }
        let fleet = [
            s("old", cwd: "/Users/x/Code/hop2/hay", at: 10),
            s("new", cwd: "/Users/x/Code/hop2", at: 99),        // same project, newer
            s("ios", cwd: "/Users/x/Code/hop-ios", at: 50),
            s("prt", cwd: "/Users/x/Code/elsewhere", at: 98, port: true),
        ]
        let projects = recentProjects(fleet)
        XCTAssertEqual(projects.map(\.path),
                       ["/Users/x/Code/hop2", "/Users/x/Code/hop-ios"],
                       "one entry per project, newest session's path wins, ports excluded")
        XCTAssertEqual(projects.first?.label, projectKey("/Users/x/Code/hop2"))
    }

    func testNeighborSessionWrapsAndRefusesToGuess() {
        func s(_ name: String, live: Bool = true) -> HopSession {
            HopSession(json: ["internalName": name, "name": name,
                              "live": live, "type": "terminal"], seenBellSeq: [:])!
        }
        let fleet = [s("a"), s("b"), s("c")]
        XCTAssertEqual(neighborSession(fleet, of: "a", step: 1)?.internalName, "b")
        XCTAssertEqual(neighborSession(fleet, of: "c", step: 1)?.internalName, "a", "wraps forward")
        XCTAssertEqual(neighborSession(fleet, of: "a", step: -1)?.internalName, "c", "wraps back")
        // Nowhere to go: lone session, or a current that already left the
        // fleet — a stale swipe must not jump somewhere random.
        XCTAssertNil(neighborSession([s("a")], of: "a", step: 1))
        XCTAssertNil(neighborSession(fleet, of: "ghost", step: 1))
        // Dead sessions are not stops on the ring.
        XCTAssertEqual(neighborSession([s("a"), s("dead", live: false), s("c")],
                                       of: "a", step: 1)?.internalName, "c")
    }

    func testMeaningfulTailIndicesAgreeWithTheStringVersion() {
        // The indices are the contract between the plain screen and its
        // colour report: mapping them back must reproduce meaningfulTail.
        let screen = "── chrome ──\n  real output here  \n❯\nanother line\nbypass permissions on\nfinal thought"
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let viaIndices = AppModel.meaningfulTailIndices(of: screen, lines: 3)
            .map { lines[$0].trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        XCTAssertEqual(viaIndices, AppModel.meaningfulTail(of: screen, lines: 3))
        XCTAssertEqual(viaIndices, "real output here\nanother line\nfinal thought")
    }

    func testTileInkTrimsRunsAtRunGranularity() {
        let runs = TileInk.decode([[
            ["t": "    "], ["t": "  lead", "f": "#ff0000"], ["t": "tail  ", "f": "#00ff00"], ["t": "   "],
        ]])[0]
        let t = TileInk.trimmed(runs)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].t, "lead")
        XCTAssertEqual(t[0].f, "#ff0000", "styling survives the cut")
        XCTAssertEqual(t[1].t, "tail")
        // A row that is nothing but space disappears entirely.
        XCTAssertTrue(TileInk.trimmed(TileInk.decode([[["t": "   "], ["t": " "]]])[0]).isEmpty)
    }

    func testTileInkSnippetPicksTheMeaningfulRows() {
        let text = "╭──────────────╮\ncolored output\n❯\nplain fallback row"
        let color: [[[String: Any]]] = [
            [["t": "╭──────────────╮"]],
            [["t": "colored output", "f": "#aabbcc"]],
            [["t": "❯"]],
            [],                                  // no colour for the last row
        ]
        let screen = ScreenPreview(text: text, cols: 80, rows: 4,
                                   colorRows: TileInk.decode(color))
        let snip = TileInk.snippet(screen, lines: 3)
        XCTAssertEqual(String(snip!.characters), "colored output\nplain fallback row")
        // No colour report at all → nil, so the caller uses the plain path.
        let bare = ScreenPreview(text: text, cols: 80, rows: 4, colorRows: [])
        XCTAssertNil(TileInk.snippet(bare, lines: 3))
    }

    func testTileInkDecodesRunsAndTolneratesJunk() {
        let rows = TileInk.decode([
            [["t": "hi", "f": "#ffcc00", "o": 1], ["t": " there", "i": 1]],
            [],
            [["notext": true]],
        ])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[0][0].t, "hi")
        XCTAssertEqual(rows[0][0].f, "#ffcc00")
        XCTAssertTrue(rows[0][0].o)
        XCTAssertFalse(rows[0][0].i)
        XCTAssertNil(rows[0][1].f)
        XCTAssertTrue(rows[0][1].i, "inverse flag survives decoding")
        XCTAssertTrue(rows[1].isEmpty)
        XCTAssertTrue(rows[2].isEmpty, "a run without text is dropped, not crashed on")
        // Absent or malformed field → empty, which means "plain render".
        XCTAssertTrue(TileInk.decode(nil).isEmpty)
        XCTAssertTrue(TileInk.decode("nope").isEmpty)
    }

    func testTileInkStylesTheSameWindowThePlainRenderShows() {
        // Colour report covers row 0 only; the window asks for rows 1..<3.
        // Row 1 must fall back to the plain line, row 2 to empty — never a
        // crash, never rows the plain render wouldn't show.
        let rows = TileInk.decode([[["t": "row0", "f": "#ff0000"]], [], []])
        let out = TileInk.attributed(rows: rows, lines: ["row0", "row1", "row2"],
                                     range: 1..<3)
        XCTAssertEqual(String(out.characters), "row1\nrow2")
    }

    func testAppTintSeparatesAppsAndDefaultsNeutral() {
        XCTAssertEqual(appTint("claude"), appTint("CLAUDE"))
        XCTAssertNotEqual(appTint("claude"), appTint("vim"))
        XCTAssertNotEqual(appTint("vim"), appTint("somethingelse"))
        XCTAssertEqual(appTint("unknown-app"), appTint("another-unknown"))
    }

    func testTileTypeDropsTrailingBlanksBeforeHistory() {
        // A 44-row grid holding 6 rows of content: the blank tail is not
        // "recent activity", it is empty screen — trim it first so the window
        // is content, then keep whatever history still fits.
        let text = "one\ntwo\nthree\nfour\nfive\nsix" + String(repeating: "\n", count: 38)
        let r = TileTypography.window(text: text, cols: 90, width: 174, height: 160)
        XCTAssertEqual(r.text, "one\ntwo\nthree\nfour\nfive\nsix")
        XCTAssertEqual(r.pt, TileTypography.floorPt)
    }
}
