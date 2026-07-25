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

    func testLocalOnlyKeysNeverNeedASocket() {
        // Arming ctrl or dismissing the keyboard must keep working while the
        // connection is down; anything that writes bytes must not.
        for key in [AccessoryKey.ctrl, .alt, .dismiss] { XCTAssertFalse(key.sendsInput) }
        for key in [AccessoryKey.esc, .tab, .ctrlC, .up, .paste, .tilde, .pageDown] {
            XCTAssertTrue(key.sendsInput)
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

    func testPortSessionsNeverAppear() {
        let list = [session(["name": "web", "type": "port"]), session(["name": "shell"])]
        XCTAssertEqual(filterSessions(list, scope: .all, query: "").map(\.name), ["shell"])
    }
}
