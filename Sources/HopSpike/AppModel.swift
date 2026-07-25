import SwiftUI
import os

// One shared model: server URL, auth state, cookie-carrying URLSession used by
// BOTH the REST calls and the terminal WebSocket (login's Set-Cookie rides
// URLSession's cookie storage into wss:// automatically).
@MainActor
final class AppModel: ObservableObject {
    /// One instance: the background-refresh handler runs outside the view
    /// tree and must talk to the same model the UI uses.
    static let shared = AppModel()

    @AppStorage("serverURL") var serverURL = "https://hop.zhoulab.io"
    @Published var authenticated = false
    @Published var checkingAuth = true
    @Published var sessions: [HopSession] = []
    @Published var lastError: String?
    /// Set when a cookie we HAD was rejected — i.e. the 7-day session ran out,
    /// as opposed to never having signed in. The difference is the difference
    /// between "did something break?" and "ah, it's been a week".
    @Published var sessionExpired = false
    /// Set by the terminal's title menu to jump straight to another session
    /// without popping back to the list.
    @Published var requestedSession: String?
    /// internalName -> last rendered screen text (the daemon renders these on
    /// demand, so only ask for what's actually on screen).
    @Published var previews: [String: String] = [:]
    // Optional access token (the daemon accepts it as Bearer / ?token=).
    // Dev/simulator runs can inject it via the HOP_DEV_TOKEN env var so the
    // real UI can be exercised without an authenticator code.
    var accessToken: String? {
        ProcessInfo.processInfo.environment["HOP_DEV_TOKEN"] ?? UserDefaults.standard.string(forKey: "accessToken")
    }

    let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared // persists across launches
        cfg.httpCookieAcceptPolicy = .always
        // waitsForConnectivity parks a request indefinitely when the server is
        // unreachable — the app sat on its launch spinner forever with no way
        // out. Fail fast instead and let the UI say what happened.
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        return URLSession(configuration: cfg)
    }()

    private var seenBells: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "seenBells") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "seenBells") }
    }

    /// What the user typed, made usable: default to https when they omit the
    /// scheme, drop trailing slashes and stray whitespace. Without this,
    /// "hop.zhoulab.io" or a pasted URL with a trailing "/" failed to log in
    /// with no explanation.
    var normalizedServerURL: String {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return s }
        if !s.contains("://") { s = "https://" + s }
        return s
    }

    var baseURL: URL? { URL(string: normalizedServerURL) }
    var wsBase: String {
        normalizedServerURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
    }

    func bootstrap() async {
        // Dev/simulator: seed the session cookie so the cookie auth path (what
        // the device uses after login) can be exercised without a TOTP code.
        // #if DEBUG so a shipping build carries no path that injects a session
        // from the environment — inert on iOS either way, but a TestFlight
        // build has no business containing it.
#if DEBUG
        if let devCookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"],
           let host = URL(string: serverURL)?.host,
           let cookie = HTTPCookie(properties: [
               .name: "tunnel_session", .value: devCookie, .domain: host,
               .path: "/", .secure: "TRUE"
           ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
#endif
        checkingAuth = true
        await refreshSessions(silent: true)
        checkingAuth = false
    }

    /// Sign out for real: the cookie is what keeps you in, so dropping only
    /// the flag would let the next launch walk straight back in. Also drops
    /// the saved password, and the badge and quick actions — both leak session
    /// names to anyone holding the phone, which is precisely who you signed
    /// out for.
    func signOut() {
        if let url = baseURL {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        Keychain.delete(account: normalizedServerURL)
        seenBells = [:]          // stale baselines would silence a new account's first bell
        sessions = []
        previews = [:]
        requestedSession = nil
        lastError = nil
        authenticated = false
        authEpoch += 1
        HopNotifier.shared.reset()
        QuickActions.clear()
    }

    func login(password: String, totp: String) async {
        lastError = nil
        guard let url = baseURL?.appendingPathComponent("api/login") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password, "totp": totp])
        do {
            let (data, resp) = try await urlSession.data(for: req)
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            if ok {
                sessionExpired = false
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

    /// Bumped on sign-out so a request already in flight can't report success
    /// afterwards and walk the user straight back in.
    private var authEpoch = 0

    func refreshSessions(silent: Bool = false) async {
        guard let url = baseURL?.appendingPathComponent("api/sessions") else { return }
        let epoch = authEpoch
        // Whether we're presenting a session cookie must be read BEFORE the
        // request: a rejected one comes back with a Set-Cookie that clears it,
        // so by the time we handle the failure the jar is already empty and
        // "expired" is indistinguishable from "never signed in".
        let hadSessionCookie = baseURL
            .flatMap { HTTPCookieStorage.shared.cookies(for: $0) }?
            .contains { $0.name == "tunnel_session" } ?? false
        var listReq = URLRequest(url: url)
        listReq.timeoutInterval = 12
        if let token = accessToken { listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await urlSession.data(for: listReq)
            guard epoch == authEpoch else { return }   // signed out mid-flight
            guard let http = resp as? HTTPURLResponse else { return }
            // Only a definitive rejection logs the user out. A transient blip
            // (timeout, tunnel hiccup, 5xx) must NOT bounce them to the login
            // screen — that made a momentary network glitch look like a lost
            // session and hid the real error.
            let isJSON = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json")
            if http.statusCode == 401 || http.statusCode == 403 || (!isJSON && http.statusCode == 200) {
                // Distinguish "expired" from "never signed in" by whether we
                // actually presented a cookie, and drop the dead one so it
                // can't keep failing quietly in the jar.
                if hadSessionCookie {
                    sessionExpired = true
                    if let url = baseURL, let stale = HTTPCookieStorage.shared.cookies(for: url)?
                        .first(where: { $0.name == "tunnel_session" }) {
                        HTTPCookieStorage.shared.deleteCookie(stale)   // dead, don't keep presenting it
                    }
                }
                authenticated = false
                return
            }
            guard http.statusCode == 200, isJSON,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["sessions"] as? [[String: Any]] else {
                if !silent { lastError = "Server returned \(http.statusCode)" }
                return
            }
            var seen = seenBells
            // Seed a silent baseline for sessions this device has never seen:
            // without a stored marker, `attention` fell back to the CURRENT
            // bellSeq and could never become true — so a session you had not
            // opened yet never rang, on the list or in notifications.
            var seeded = false
            for s in raw {
                guard let key = (s["internalName"] as? String) ?? (s["name"] as? String) else { continue }
                if seen[key] == nil {
                    seen[key] = jsonInt(s["bellSeq"]) ?? 0
                    seeded = true
                }
            }
            if seeded { seenBells = seen }
            // HOP_DEV_ATTENTION=1 forces the first session into the attention
            // state: otherwise the design of the thing the app is FOR can only
            // be reviewed by waiting for an agent to ring. DEBUG-only — it
            // fakes app state, which has no place in a shipping build.
#if DEBUG
            if ProcessInfo.processInfo.environment["HOP_DEV_ATTENTION"] == "1", let first = raw.first,
               let key = (first["internalName"] as? String) ?? (first["name"] as? String) {
                seen[key] = (jsonInt(first["bellSeq"]) ?? 0) - 1   // -1 is fine: any bellSeq beats it
            }
#endif
            sessions = raw.compactMap { HopSession(json: $0, seenBellSeq: seen) }
                .sorted { ($0.attention ? 1 : 0, $0.lastActivityAt) > ($1.attention ? 1 : 0, $1.lastActivityAt) }
            authenticated = true
            // A refresh that worked is proof the last failure is over. Without
            // this, one tunnel blip pinned a red banner to the top of the list
            // for the rest of the session, through every successful refresh
            // after it.
            lastError = nil
            // Drop previews for sessions that are gone: otherwise a killed
            // session's last screen sits in memory, and a name reused later
            // would show it as if it were live.
            for s in sessions { lastKnown[s.internalName] = s }
            let alive = Set(sessions.map(\.internalName))
            previews = previews.filter { alive.contains($0.key) }
            // Watching a session counts as seeing its bells: keep the marker
            // current so backing out doesn't leave a stale attention dot, and
            // never banner the terminal that's on screen.
            if let open = watching, let shown = sessions.first(where: { $0.internalName == open }),
               seenBells[open] != shown.bellSeq {
                markSeen(shown)
            }
            HopNotifier.shared.report(attention: alertable(sessions, openSession: watching))
            QuickActions.publish(sessions)
        } catch {
            // Network failure: keep the user where they are, surface the reason.
            // Offline is worth naming — otherwise the phone having no signal
            // reads as "the daemon is broken", which sends you to the wrong
            // place entirely.
            lastError = NetworkConditions.shared.isOnline
                ? error.localizedDescription
                : "No internet connection"
        }
    }

    // ── Session management (parity with the web session manager) ──
    private func post(_ path: String, _ body: [String: Any]) async -> Bool {
        guard let url = baseURL?.appendingPathComponent(path) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await urlSession.data(for: req)
            let ok = (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 500)
            if ok {
                await refreshSessions(silent: true)
            } else {
                // hop says WHY ("invalid session name", "already exists").
                // "Request failed" threw that away and left the user guessing
                // at a dialog that just closed and did nothing.
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                lastError = (obj?["error"] as? String) ?? "Request failed"
            }
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createSession(name: String) async -> Bool {
        await post("api/sessions", ["name": name, "type": "terminal"])
    }
    func renameSession(_ s: HopSession, to newName: String) async -> Bool {
        await post("api/sessions/rename", ["oldName": s.name, "newName": newName])
    }
    func setAgentAccess(_ s: HopSession, allowed: Bool) async -> Bool {
        await post("api/sessions/agent-permission", ["internalName": s.internalName, "allowed": allowed])
    }
    func killSession(_ s: HopSession) async -> Bool {
        await post("api/sessions/delete", ["internalName": s.internalName])
    }

    /// Fetch screen previews for the sessions the user can actually see.
    /// Mirrors the web switcher: bounded set, only while the list is open.
    func refreshPreviews(for names: [String]) async {
        await withTaskGroup(of: (String, String?).self) { group in
            for name in names.prefix(6) {
                group.addTask { [weak self] in
                    guard let self else { return (name, nil) }
                    return (name, await self.fetchPreview(name))
                }
            }
            for await (name, text) in group {
                if let text, !text.isEmpty { previews[name] = text }
            }
        }
    }

    /// hop can search the scrollback of every session at once. The local
    /// filter only matches names, cwds and taglines — but the question you
    /// actually have on a phone is "which session mentioned that error", and
    /// you can't answer it by opening thirty terminals.
    func searchContent(_ query: String) async -> [ContentMatch] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        guard var comps = baseURL.map({ $0.appendingPathComponent("api/sessions/search") })
            .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return [] }
        comps.queryItems = [.init(name: "q", value: q)]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await urlSession.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["matches"] as? [[String: Any]] else { return [] }
        return raw.compactMap { m in
            guard let internalName = m["internalName"] as? String else { return nil }
            return ContentMatch(internalName: internalName,
                                name: (m["name"] as? String) ?? internalName,
                                snippet: (m["snippet"] as? String) ?? "")
        }
    }

    private func fetchPreview(_ internalName: String) async -> String? {
        guard var comps = baseURL.map({ $0.appendingPathComponent("api/sessions/preview") })
            .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        comps.queryItems = [.init(name: "name", value: internalName)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await urlSession.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { return nil }
        return Self.meaningfulTail(of: text, lines: 3)
    }

    /// The last few lines that actually say something. A TUI's final lines are
    /// its own chrome — Claude's composer box, rule lines, the "bypass
    /// permissions" hint — so a naive tail shows every session as identical
    /// box-drawing. Skip chrome and keep real content.
    nonisolated static func meaningfulTail(of screen: String, lines wanted: Int) -> String {
        let boxChars = CharacterSet(charactersIn: "─│╭╮╰╯┌┐└┘├┤┬┴┼━┃▏▕▁▔█▀▄· ")
        let noise = ["bypass permissions", "esc to interrupt", "shift+tab to cycle",
                     "? for shortcuts", "ctrl+c to"]
        let kept = screen.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                if noise.contains(where: { lower.contains($0) }) { return false }
                // Prompt-only lines ("❯", "> ") carry no information.
                if line.count <= 2 { return false }
                // Mostly box-drawing => chrome.
                let boxCount = line.unicodeScalars.filter { boxChars.contains($0) }.count
                return Double(boxCount) / Double(line.unicodeScalars.count) < 0.6
            }
        return kept.suffix(wanted).joined(separator: "\n")
    }

    /// Every session seen this launch. A session that ends while you're
    /// reading it drops out of `sessions` on the next refresh, and the
    /// navigation destination then had nothing to render — the screen went
    /// blank and took the final output with it. Falling back to the last known
    /// value keeps the terminal (and its "[session ended]" line) on screen.
    private(set) var lastKnown: [String: HopSession] = [:]

    /// The session currently on screen, if any. A bell from the terminal
    /// you're staring at is not news.
    var openSession: String?

    /// Whether the app is actually in front. Without this, locking the phone
    /// with a terminal open would keep suppressing that session's
    /// notifications — silencing the exact session you were waiting on, which
    /// is the app's whole reason to exist.
    var foreground = true

    /// The session being watched RIGHT NOW: only counts while in front.
    private var watching: String? { foreground ? openSession : nil }

    func markSeen(_ session: HopSession) {
        var seen = seenBells
        seen[session.internalName] = session.bellSeq
        seenBells = seen
        HopNotifier.shared.clear(session.internalName)
    }
}

/// Shared with HayClient: the same coercion applies to every JSON number the
/// app reads, over HTTP or over the socket.
///
/// JSON numbers arrive as Int or Double depending on the encoder, and a
/// straight `as? Double` / `as? Int` silently yields nil for the other form —
/// which would zero out lastActivityAt (breaking ordering) or bellSeq
/// (breaking attention) with no error anywhere. Coerce instead.
func jsonDouble(_ any: Any?) -> Double? {
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    if let n = any as? NSNumber { return n.doubleValue }
    return nil
}

func jsonInt(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let d = any as? Double { return Int(d) }
    if let n = any as? NSNumber { return n.intValue }
    return nil
}

/// A hit from hop's cross-session scrollback search.
struct ContentMatch: Identifiable {
    let internalName: String
    let name: String
    let snippet: String
    var id: String { internalName }
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
    let createdBy: String
    let tagline: String
    let agentPermitted: Bool
    var id: String { internalName }

    init?(json: [String: Any], seenBellSeq: [String: Int]) {
        guard let n = (json["displayName"] as? String) ?? (json["name"] as? String) else { return nil }
        name = n
        internalName = (json["internalName"] as? String) ?? n
        cwd = (json["cwd"] as? String) ?? ""
        foregroundProcess = (json["foregroundProcess"] as? String) ?? ""
        lastActivityAt = jsonDouble(json["lastActivityAt"]) ?? 0
        bellSeq = jsonInt(json["bellSeq"]) ?? 0
        live = (json["live"] as? Bool) ?? false
        isPort = (json["type"] as? String) == "port"
        attention = bellSeq > (seenBellSeq[internalName] ?? bellSeq)
        agentPermitted = (json["agentPermitted"] as? Bool) ?? false
        createdBy = (json["createdBy"] as? String) ?? "user"
        tagline = (json["tagline"] as? String) ?? ""

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
        let p = foregroundProcess.trimmingCharacters(in: .whitespaces)
        let shells: Set<String> = ["zsh", "bash", "sh", "fish", "-zsh", "login", "node"]
        if p.isEmpty || shells.contains(p) { return "" }
        // claude retitles its process to its VERSION ("2.1.220") — a bare
        // version tells the user nothing, so name the app instead.
        if p.range(of: #"^v?\d+(\.\d+)+$"#, options: .regularExpression) != nil { return "claude" }
        return p
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
