import Foundation

// Minimal client for the hay room protocol (see hop2/hay/README.md):
// connect wss://host/ws?room=X&name=Y&cols=N&rows=M, then JSON messages.
final class HayClient: NSObject {
    enum Event {
        case connected
        case output(String)          // raw terminal bytes (snapshot or live)
        case activeSize(Int, Int)    // cols, rows
        case ended(String)
        case failed(String)          // human-readable reason (auth, network, …)
        case closed
    }

    private var task: URLSessionWebSocketTask?
    var onEvent: ((Event) -> Void)?

    func connect(base: String, httpBase: String, room: String, cols: Int, rows: Int,
                 token: String?, using session: URLSession) {
        var comps = URLComponents(string: base + "/ws")
        var items: [URLQueryItem] = [
            .init(name: "room", value: room),
            .init(name: "name", value: "iPhone"),
            .init(name: "source", value: "ios"),
            .init(name: "cols", value: String(cols)),
            .init(name: "rows", value: String(rows))
        ]
        // The daemon accepts cookie, Bearer, or ?token= on the upgrade.
        if let token, !token.isEmpty { items.append(.init(name: "token", value: token)) }
        comps?.queryItems = items
        guard let url = comps?.url else {
            onEvent?(.failed("Bad server URL"))
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
    func sendResize(cols: Int, rows: Int) { sendJSON(["type": "resize", "cols": cols, "rows": rows]) }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // A rejected upgrade surfaces as an error here; name it so the
                // user sees "not authorized" rather than a bare "disconnected".
                let ns = error as NSError
                let reason: String
                let status = (self.task?.response as? HTTPURLResponse)?.statusCode
                // 101 = Switching Protocols: the upgrade SUCCEEDED, so this is a
                // post-connect failure (message too large, server close, network).
                if let status, status != 101 {
                    switch status {
                    case 401, 403: reason = "not authorized — sign in again"
                    case 404: reason = "session not found on the server"
                    default: reason = "server refused the connection (\(status))"
                    }
                } else if ns.domain == NSURLErrorDomain {
                    reason = ns.localizedDescription
                } else {
                    reason = "connection lost: \(ns.localizedDescription)"
                }
                DispatchQueue.main.async { self.onEvent?(.failed(reason)) }
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
            onEvent?(.connected)
        case "snapshot", "output":
            if let payload = obj["data"] as? String { onEvent?(.output(payload)) }
        case "active_size":
            if let c = obj["cols"] as? Int, let r = obj["rows"] as? Int { onEvent?(.activeSize(c, r)) }
        case "session_ended":
            onEvent?(.ended((obj["message"] as? String) ?? "Session ended"))
        default:
            break
        }
    }
}
