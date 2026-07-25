import SwiftUI

// One shared model: server URL, auth state, cookie-carrying URLSession used by
// BOTH the REST calls and the terminal WebSocket (login's Set-Cookie rides
// URLSession's cookie storage into wss:// automatically).
@MainActor
final class AppModel: ObservableObject {
    @AppStorage("serverURL") var serverURL = "https://hop.zhoulab.io"
    @Published var authenticated = false
    @Published var checkingAuth = true
    @Published var sessions: [HopSession] = []
    @Published var lastError: String?

    let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared // persists across launches
        cfg.httpCookieAcceptPolicy = .always
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private var seenBells: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "seenBells") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "seenBells") }
    }

    var baseURL: URL? { URL(string: serverURL) }
    var wsBase: String {
        serverURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
    }

    func bootstrap() async {
        checkingAuth = true
        await refreshSessions(silent: true)
        checkingAuth = false
    }

    func login(password: String, totp: String) async {
        lastError = nil
        guard let url = baseURL?.appendingPathComponent("api/login") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password, "totp": totp])
        do {
            let (data, resp) = try await urlSession.data(for: req)
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            if ok {
                authenticated = true
                await refreshSessions(silent: true)
            } else {
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                lastError = (obj?["error"] as? String) ?? "Login failed"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshSessions(silent: Bool = false) async {
        guard let url = baseURL?.appendingPathComponent("api/sessions") else { return }
        do {
            let (data, resp) = try await urlSession.data(from: url)
            guard let http = resp as? HTTPURLResponse else { return }
            // The daemon redirects unauthenticated API hits to the login page.
            let isJSON = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json")
            guard http.statusCode == 200, isJSON,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["sessions"] as? [[String: Any]] else {
                authenticated = false
                return
            }
            let seen = seenBells
            sessions = raw.compactMap { HopSession(json: $0, seenBellSeq: seen) }
                .sorted { ($0.attention ? 1 : 0, $0.lastActivityAt) > ($1.attention ? 1 : 0, $1.lastActivityAt) }
            authenticated = true
        } catch {
            if !silent { lastError = error.localizedDescription }
        }
    }

    func markSeen(_ session: HopSession) {
        var seen = seenBells
        seen[session.internalName] = session.bellSeq
        seenBells = seen
    }
}

struct HopSession: Identifiable {
    let name: String
    let internalName: String
    let cwd: String
    let foregroundProcess: String
    let lastActivityAt: Double
    let bellSeq: Int
    let live: Bool
    let isPort: Bool
    let attention: Bool
    var id: String { internalName }

    init?(json: [String: Any], seenBellSeq: [String: Int]) {
        guard let n = (json["displayName"] as? String) ?? (json["name"] as? String) else { return nil }
        name = n
        internalName = (json["internalName"] as? String) ?? n
        cwd = (json["cwd"] as? String) ?? ""
        foregroundProcess = (json["foregroundProcess"] as? String) ?? ""
        lastActivityAt = (json["lastActivityAt"] as? Double) ?? 0
        bellSeq = (json["bellSeq"] as? Int) ?? 0
        live = (json["live"] as? Bool) ?? false
        isPort = (json["type"] as? String) == "port"
        attention = bellSeq > (seenBellSeq[internalName] ?? bellSeq)
    }

    var shortCwd: String {
        guard !cwd.isEmpty else { return "" }
        var display = cwd
        if let r = cwd.range(of: #"^/(Users|home)/[^/]+"#, options: .regularExpression) {
            display = "~" + cwd[r.upperBound...]
        }
        return display
    }

    var runningApp: String {
        let shells: Set<String> = ["zsh", "bash", "sh", "fish", "-zsh", "login"]
        return shells.contains(foregroundProcess) ? "" : foregroundProcess
    }

    var relativeTime: String {
        guard lastActivityAt > 0 else { return "" }
        let s = Int(Date().timeIntervalSince1970 - lastActivityAt / 1000)
        if s < 10 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
