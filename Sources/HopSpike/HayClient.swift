import Foundation
import os

// Minimal client for the hay room protocol (see hop2/hay/README.md):
// connect wss://host/ws?room=X&name=Y&cols=N&rows=M, then JSON messages.
final class HayClient: NSObject {
    enum Event {
        case connected
        case output(String)
        // Full replay. The mode flags travel BESIDE the data because the
        // replayed bytes don't re-emit the DECSETs that turned them on — the
        // app enabled alt-screen once, long before this tail begins.
        case snapshot(String, alternateScreen: Bool, cursorHidden: Bool)          // raw terminal bytes (snapshot or live)
        case activeSize(Int, Int)    // cols, rows
        case presence([Viewer])      // who else is attached
        case collab(Bool, String?)   // everyone-can-type, controllerId
        case rejected(String)        // input refused (control locked)
        case ended(String)
        // `permanent` means retrying cannot help: the room is gone, or this
        // device isn't allowed in. Backing off forever against a 404 just
        // burns radio and repeats the same error at the user.
        case failed(String, permanent: Bool)
        case renamed(String)         // display name changed elsewhere
        case serverError(String)     // the server rejected something we sent
        case closed
    }

    struct Viewer: Identifiable, Equatable {
        let id: String
        let name: String
        let typing: Bool
    }

    /// This client's id, from the server's hello — needed to tell "I hold
    /// control" from "someone else does".
    private(set) var clientId: String?

    private var task: URLSessionWebSocketTask?
    var onEvent: ((Event) -> Void)?

    /// Enough to redraw a TUI screen and leave a little shell history, and
    /// small enough that opening a session on cellular is not an event.
    static let replayBytes = 200_000
    private var replayBytes: Int { Self.replayBytes }

    func connect(base: String, httpBase: String, room: String, cols: Int, rows: Int,
                 token: String?, using session: URLSession) {
        var comps = URLComponents(string: base + "/ws")
        var items: [URLQueryItem] = [
            .init(name: "room", value: room),
            .init(name: "name", value: "iPhone"),
            .init(name: "source", value: "ios"),
            .init(name: "cols", value: String(cols)),
            .init(name: "rows", value: String(rows)),
            // A phone doesn't need a desktop's worth of replay: hop's default
            // tail is 1.5 MB raw, which measured 2.4 MB on the wire as JSON
            // and yielded one screen. The server clamps this to its own bound,
            // and ignores it entirely on versions that don't read it yet.
            .init(name: "replayBytes", value: String(replayBytes))
        ]
        // The daemon accepts cookie, Bearer, or ?token= on the upgrade.
        if let token, !token.isEmpty { items.append(.init(name: "token", value: token)) }
        comps?.queryItems = items
        guard let url = comps?.url else {
            onEvent?(.failed("Bad server URL", permanent: true))   // retrying can't fix a URL
            return
        }

        var req = URLRequest(url: url)
        // `Cookie` is a RESERVED header: URLSession overwrites/strips a manually
        // set one while it manages cookies itself — and for a wss:// URL its own
        // jar lookup skips Secure cookies (scheme isn't https), so neither path
        // sent it and the daemon 401'd the upgrade (502 through Cloudflare).
        // Turning off automatic handling is what makes the explicit header stick.
        req.httpShouldHandleCookies = false
        // URLSession does NOT attach Secure cookies to a wss:// URL — its scheme
        // isn't https, so the cookie jar skips it and the daemon 401s the
        // upgrade (while plain https REST calls succeed). Carry the session
        // cookie explicitly, looked up against the https origin that set it.
        if let httpURL = URL(string: httpBase),
           let cookies = HTTPCookieStorage.shared.cookies(for: httpURL), !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                req.setValue(value, forHTTPHeaderField: field)
            }
        }
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let t = session.webSocketTask(with: req)
        // hop replays a JOIN SNAPSHOT of up to ~1.5 MB (HAY_SNAPSHOT_REPLAY_BYTES)
        // in a single message. URLSessionWebSocketTask's default cap is 1 MB, so
        // any session with real scrollback blew the limit and the task failed
        // right after a SUCCESSFUL upgrade (HTTP 101) — which read like a refused
        // connection. Allow room for the largest snapshot plus headroom.
        t.maximumMessageSize = 32 * 1024 * 1024
        task = t
        t.resume()
        receiveLoop()
    }

    func sendInput(_ text: String) { sendJSON(["type": "input", "data": text]) }
    func takeControl() { sendJSON(["type": "take_control"]) }
    func releaseControl() { sendJSON(["type": "release_control"]) }
    func setCollab(_ enabled: Bool) { sendJSON(["type": "toggle_collab", "enabled": enabled]) }
    /// `claim: "attach"` marks the first fit after opening a session. hop's
    /// size election normally needs every peer input-idle for 60s; an attach
    /// claim only needs 2.5s, because opening a session somewhere is a
    /// deliberate act. Without it the phone loses to any desktop that typed in
    /// the last minute and renders at ITS width — mis-wrapped until you type.
    /// Presence only: the size election runs off real input, not this flag.
    /// Without it a desktop peer never sees that the phone is mid-command.
    func sendTyping(_ active: Bool) { sendJSON(["type": "typing", "active": active]) }

    func sendResize(cols: Int, rows: Int, claim: String? = nil) {
        var msg: [String: Any] = ["type": "resize", "cols": cols, "rows": rows]
        if let claim { msg["claim"] = claim }
        sendJSON(msg)
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    private var connectedAt: Date?

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // A rejected upgrade surfaces as an error here; name it so the
                // user sees "not authorized" rather than a bare "disconnected".
                let ns = error as NSError
                let reason: String
                var permanent = false
                let status = (self.task?.response as? HTTPURLResponse)?.statusCode
                // 101 = Switching Protocols: the upgrade SUCCEEDED, so this is a
                // post-connect failure (message too large, server close, network).
                if let status, status != 101 {
                    switch status {
                    case 401, 403:
                        reason = "not authorized — sign in again"
                        permanent = true
                    case 404:
                        reason = "session not found on the server"
                        permanent = true
                    default: reason = "server refused the connection (\(status))"
                    }
                } else if ns.domain == NSURLErrorDomain {
                    reason = ns.localizedDescription
                } else {
                    reason = "connection lost: \(ns.localizedDescription)"
                }
                let isPermanent = permanent
                DispatchQueue.main.async { self.onEvent?(.failed(reason, permanent: isPermanent)) }
            case .success(let message):
                if case .string(let text) = message {
                    DispatchQueue.main.async { self.handle(text) }
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "hello":
            connectedAt = Date()
            clientId = obj["clientId"] as? String
            onEvent?(.connected)
            if let collabMode = obj["collabMode"] as? Bool {
                onEvent?(.collab(collabMode, obj["controllerId"] as? String))
            }
        case "presence":
            let clients = (obj["clients"] as? [[String: Any]]) ?? []
            onEvent?(.presence(clients.compactMap { c in
                guard let id = c["id"] as? String else { return nil }
                return Viewer(id: id, name: (c["name"] as? String) ?? "someone",
                              typing: (c["typing"] as? Bool) ?? false)
            }))
        case "collab":
            onEvent?(.collab((obj["enabled"] as? Bool) ?? true, obj["controllerId"] as? String))
        case "input_rejected":
            onEvent?(.rejected((obj["reason"] as? String) ?? "Input rejected"))
        case "snapshot", "output":
            if type == "snapshot" {
                // What reattaching actually costs. hop replays its whole
                // buffer on join and offers no way to ask for less, so this is
                // the number that decides how an open feels on cellular.
                let bytes = text.utf8.count
                let ms = connectedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
                Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                    .info("snapshot \(bytes / 1024) KB after \(ms) ms")
            }
            if let payload = obj["data"] as? String {
                if type == "snapshot" {
                    onEvent?(.snapshot(payload,
                                       alternateScreen: (obj["alternateScreen"] as? Bool) ?? false,
                                       cursorHidden: (obj["cursorHidden"] as? Bool) ?? false))
                } else {
                    onEvent?(.output(payload))
                }
            }
        case "active_size":
            // Coerced rather than `as? Int`: a JSON number arriving as a
            // Double silently yields nil, which is exactly the bug that once
            // zeroed lastActivityAt and bellSeq.
            if let c = jsonInt(obj["cols"]), let r = jsonInt(obj["rows"]) {
                onEvent?(.activeSize(c, r))
            }
        case "session_renamed":
            if let name = obj["displayName"] as? String, !name.isEmpty { onEvent?(.renamed(name)) }
        case "error":
            // The server sends this when WE send something it can't parse. It
            // was being dropped, so a protocol drift after a hop update would
            // have broken input with no signal anywhere.
            onEvent?(.serverError((obj["message"] as? String) ?? "Server rejected a message"))
        case "session_ended":
            onEvent?(.ended((obj["message"] as? String) ?? "Session ended"))
        case "pong", "cwd_changed":
            break        // pong: we never ping. cwd: the list refresh carries it.
        default:
            // Naming what we ignore is how the next protocol addition gets
            // noticed instead of silently dropped, as these four were.
            Logger(subsystem: "io.zhoulab.hop.spike", category: "protocol")
                .info("unhandled server message \(type, privacy: .public)")
        }
    }
}
