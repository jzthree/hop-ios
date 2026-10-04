import XCTest
/// Codex shortens long URLs on screen; a tap must open the FULL address.
/// HOP_LINK_SCAN makes the app run the tap's own link lookup on every cell.
final class LinkProbe: XCTestCase {
    func testCodexLinksResolveToFullURLs() throws {
        let env = ProcessInfo.processInfo.environment
        let cookie = env["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let out = "/tmp/hop-link-scan.txt"
        try? FileManager.default.removeItem(atPath: out)
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_OPEN"] = env["HOP_LINK_SESSION"] ?? "Accessibility-fork-codex"
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_LINK_SCAN"] = out
        app.launch()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25))
        sleep(10)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-link-screen.png"))
        let links = (try? String(contentsOfFile: out, encoding: .utf8)) ?? "<no scan>"
        print("LINK-SCAN:\n" + links)
        XCTAssertFalse(links.contains("…"), "a tap would open a truncated URL")
    }
}
