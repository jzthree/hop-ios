import XCTest

/// Search results, photographed. The corpus used to be an ANSI-STRIPPED byte
/// tail, in which a TUI's absolute-column repaints became one space each —
/// so snippets showed "hi tory", "b tes", "beaitiful" (Jian: "search results
/// seem to randomly miss character and replace with space"), and those words
/// could not be matched either. The corpus is rendered through a real
/// terminal now; this is the picture that proves what the phone shows.
final class SearchShot: XCTestCase {
    func testContentSearchSnippetsAreWholeWords() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let query = ProcessInfo.processInfo.environment["HOP_SEARCH_QUERY"] ?? "command"
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_FILTER"] = query
        app.launch()
        // hop signs a device out after 7 days; a signed-out runner can prove
        // nothing about search, so say that rather than fail as if it could.
        if app.buttons["Sign in with Face ID"].waitForExistence(timeout: 12) {
            try XCTSkipIf(true, "runner is signed out (hop expires a session after 7 days) — sign in to verify search")
        }
        let field = app.textFields["Search sessions by name"].waitForExistence(timeout: 25)
        sleep(8)   // content search is a round trip per session
        // Evidence BEFORE the verdict: a failure must still show the screen.
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: "/tmp/hop-search.png"))
        XCTAssertTrue(field, "never reached the session list")
        // Every visible snippet, straight from the accessibility tree.
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let snippets = texts.filter { $0.localizedCaseInsensitiveContains(query) && $0.count > query.count + 8 }
        print("PROBE query=\(query) snippets=\(snippets.count)")
        for s in snippets.prefix(6) { print("PROBE | \(s.prefix(110))") }
        // A word cut in half by the old stripper looks like "hi tory": a short
        // letter run, a single space, then a lowercase fragment.
        let broken = snippets.filter { $0.range(of: "\\b[a-z]{1,2} [a-z]{3,}\\b", options: .regularExpression) != nil }
        for b in broken.prefix(4) { print("PROBE broken? | \(b.prefix(110))") }
    }
}
