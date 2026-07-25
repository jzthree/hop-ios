import Foundation

// Minimal client for the hay room protocol (see hop2/hay/README.md):
// connect wss://host/ws?room=X&name=Y&cols=N&rows=M, then JSON messages.
// Auth rides the URLSession's cookie storage (login sets the session cookie).
final class HayClient: NSObject {
    enum Event {
        case connected
        case output(String)          // raw terminal bytes (snapshot or live)
        case activeSize(Int, Int)    // cols, rows
        case ended(String)
        case closed
    }

    private var task: URLSessionWebSocketTask?
    var onEvent: ((Event) -> Void)?

    func connect(base: String, room: String, cols: Int, rows: Int, using session: URLSession) {
        var comps = URLComponents(string: base + "/ws")
        comps?.queryItems = [
            .init(name: "room", value: room),
            .init(name: "name", value: "iPhone"),
            .init(name: "cols", value: String(cols)),
            .init(name: "rows", value: String(rows))
        ]
        guard let url = comps?.url else { return }
        let t = session.webSocketTask(with: url)
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
            case .failure:
                DispatchQueue.main.async { self.onEvent?(.closed) }
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
