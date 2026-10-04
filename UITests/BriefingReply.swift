import XCTest
/// A DECIDE reply chip must type its reply into the session (+ Enter).
final class BriefingReply: XCTestCase {
    private func post(_ path: String, _ body: [String: Any], _ cookie: String) -> Data? {
        var req = URLRequest(url: URL(string: "https://hop.zhoulab.io/\(path)")!)
        req.httpMethod = body.isEmpty ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("tunnel_session=\(cookie)", forHTTPHeaderField: "Cookie")
        if !body.isEmpty { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        var out: Data?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200 { out = d ?? Data() }; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return out
    }
    func testReplyChipSendsToTheSession() throws {
        let cookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"] ?? ""
        try XCTSkipUnless(!cookie.isEmpty)
        let scratch = "ReplyChipProbe"
        _ = post("api/sessions/delete", ["name": scratch], cookie)
        sleep(1)
        XCTAssertNotNil(post("api/sessions", ["name": scratch, "type": "terminal"], cookie))
        defer { _ = post("api/sessions/delete", ["name": scratch], cookie) }
        sleep(2)
        // Real briefings name sessions by internalName (minted ids).
        var room = scratch
        if let d = post("api/sessions", [:], cookie),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let list = obj["sessions"] as? [[String: Any]],
           let me = list.first(where: { ($0["name"] as? String) == scratch }),
           let id = me["internalName"] as? String { room = id }
        let digest: [String: Any] = [
            "generated_at": "2026-10-04T12:00:00.000Z", "summary": "One decision waits.",
            "items": [["session": room, "slot": "decide", "urgency": "needs-you",
                       "headline": "Pick one", "why": "Probe.", "recommendation": "Send it.",
                       "replies": ["echo chip-sent-42", "Hold"]]]
        ]
        let path = "/tmp/hop-dev-digest.json"
        try JSONSerialization.data(withJSONObject: digest).write(to: URL(fileURLWithPath: path))
        let app = XCUIApplication()
        app.launchEnvironment["HOP_DEV_COOKIE"] = cookie
        app.launchArguments += ["-hop-ui-testing"]
        app.launchEnvironment["HOP_DEV_SCOPE"] = "all"
        app.launchEnvironment["HOP_DEV_DIGEST"] = path
        app.launch()
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reply echo chip-sent-42'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "no reply chip")
        chip.tap()
        let sent = app.buttons.matching(NSPredicate(format: "label == 'Sent: echo chip-sent-42'")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "chip never confirmed")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hop-reply-chip.png"))
        XCTAssertFalse(app.buttons["escape"].exists, "a chip tap opened the session")
        // The session actually received it: the shell ran the echo.
        var landed = false
        for _ in 0..<10 {
            sleep(1)
            if let d = post("api/sessions/preview?name=\(room)", [:], cookie),
               let s = String(data: d, encoding: .utf8), s.components(separatedBy: "chip-sent-42").count >= 3 { landed = true; break }
        }
        XCTAssertTrue(landed, "reply never reached the session")
    }
}
