import XCTest

// The product-video tour, driven as real gestures so a simulator screen
// recording (xcrun simctl io … recordVideo) shows the app as it behaves:
// the wall with the briefing, a scroll, a tap into a session, typing with
// the keyboard up, and back. Pointed at the capture rig's isolated daemon
// through HOP_DEV_SERVER so only the demo cast is ever on camera.
//
//   TEST_RUNNER_HOP_DEV_SERVER=http://127.0.0.1:PORT TEST_RUNNER_HOP_DEV_COOKIE=… \
//   TEST_RUNNER_HOP_CAPTURE_OPEN=Aurora xcodebuild test … -only-testing:HopSpikeUITests/WallCapture
final class WallCapture: XCTestCase {
    func testTourForTheVideo() throws {
        let env = ProcessInfo.processInfo.environment
        let cookie = env["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty, "HOP_DEV_COOKIE not set")
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        if let server = env["HOP_DEV_SERVER"], !server.isEmpty { app.launchEnvironment["HOP_DEV_SERVER"] = server }
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launch()

        let open = env["HOP_CAPTURE_OPEN"] ?? "Aurora"
        // The wall: give the briefing and the tiles a moment to paint. A row
        // is a NavigationLink whose accessibility label is its spoken summary,
        // which starts with the session's name.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", open)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the wall never showed \(open)")
        sleep(4)
        // A slow scroll down and back — the wall breathing under a thumb.
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let up = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        mid.press(forDuration: 0.05, thenDragTo: up, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(2)
        up.press(forDuration: 0.05, thenDragTo: mid, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(2)
        // Into a session.
        row.tap()
        XCTAssertTrue(app.buttons["escape"].waitForExistence(timeout: 25), "the terminal did not open")
        sleep(3)
        // Type with the keyboard up — the feel of the app is the shot.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        sleep(1)
        app.typeText("ls -1")
        sleep(1)
        app.typeText("\n")
        sleep(4)
        if app.buttons["hide keyboard"].firstMatch.exists { app.buttons["hide keyboard"].firstMatch.tap() }
        sleep(2)
        // Back to the wall.
        let back = app.buttons["Back to sessions"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        sleep(3)
    }
}
