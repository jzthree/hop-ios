@preconcurrency import CoreSpotlight
import SwiftUI
import WidgetKit
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
    /// A failure of something the user just DID — rename, kill, reply, allow
    /// agent access — as opposed to a connectivity problem.
    ///
    /// Separate from `lastError` because the two clear on opposite signals. A
    /// successful refresh proves connectivity is back, so it clears
    /// `lastError`; it proves nothing about a rename the daemon rejected as a
    /// duplicate. Sharing one field meant every action failure was wiped by
    /// the next poll — under five seconds on wifi — so the user saw a dialog
    /// close and, quite often, nothing else at all.
    @Published var actionError: String?
    /// Set when a cookie we HAD was rejected — i.e. the 7-day session ran out,
    /// as opposed to never having signed in. The difference is the difference
    /// between "did something break?" and "ah, it's been a week".
    @Published var sessionExpired = false
    /// Set by the terminal's title menu to jump straight to another session
    /// without popping back to the list.
    @Published var requestedSession: String?
    /// The host agent's briefing, if one has been written since we last looked.
    @Published var digest: HopDigest?

    /// Fetched from the directory the daemon already serves under /assets/,
    /// with the cookie the app already holds — so this costs no new endpoint
    /// and nothing on the phone. Absent is the normal state, not an error:
    /// the file only exists once the scheduled job has run.
    func refreshDigest() async {
        guard let url = baseURL?.appendingPathComponent("assets/digest.json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let (data, resp) = try? await urlSession.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let d = HopDigest(json: obj) {
            if digest != d { digest = d }
            UserDefaults.standard.set(data, forKey: "lastDigest")
            return
        }
        // The served file is a casualty of every web rebuild (the dist is
        // wiped and rebuilt; the 17:06 briefing was simply GONE by evening).
        // The generator now writes to both roots, and this keeps the last
        // fetched copy so a wiped file can never blank the morning page.
        if digest == nil,
           let data = UserDefaults.standard.data(forKey: "lastDigest"),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let d = HopDigest(json: obj) {
            digest = d
        }
    }
    /// internalName -> last rendered screen text (the daemon renders these on
    /// demand, so only ask for what's actually on screen).
    @Published var previews: [String: String] = [:]
    /// Server-owned folders, in the daemon's order. User-authored structure
    /// — the wall's "By folder" grouping renders exactly this.
    @Published var folders: [HopFolder] = []
    /// Whole screens for tile mode: rendered text plus the grid's true column
    /// count, so a tile can scale type to the session's real geometry — the
    /// same shape the web switcher renders. Fetched from /api/sessions/screen,
    /// the endpoint the fast paint already uses (~2 KB a screen).
    @Published var screens: [String: ScreenPreview] = [:]
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
        // normalizedServerURL, NOT the raw stored value: a schemeless
        // "hop.zhoulab.io" parses with a nil host, and the seed silently
        // no-ops — which wiped out an entire UI suite (every test bounced to
        // login) the first time a schemeless value landed in the container.
        // Requests always normalized; the seed must too.
        if let devCookie = ProcessInfo.processInfo.environment["HOP_DEV_COOKIE"],
           let host = URL(string: normalizedServerURL)?.host,
           let cookie = HTTPCookie(properties: [
               .name: "tunnel_session", .value: devCookie, .domain: host,
               .path: "/", .secure: "TRUE"
           ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
#endif
        // Instant launch: paint the last known wall before the network
        // answers. Only when some credential exists — a cache render over a
        // signed-out state would flash session content on a login screen.
        if sessions.isEmpty, let cached = FleetCache.load(),
           hasAnyCredential, !cached.sessions.isEmpty {
            lastRawSessions = cached.sessions
            previews = cached.previews
            screensRaw = cached.screens
            lastRawFolders = cached.folders
            folders = cached.folders.compactMap(HopFolder.init(json:))
            sessions = cached.sessions.compactMap { HopSession(json: $0, seenBellSeq: seenBells) }
                .sorted { ($0.attention ? 1 : 0, $0.lastActivityAt) > ($1.attention ? 1 : 0, $1.lastActivityAt) }
            for s in sessions { lastKnown[s.internalName] = s }
            screens = screensRaw.compactMapValues { d in
                guard let text = d["text"] as? String else { return nil }
                return ScreenPreview(text: text,
                                     cols: jsonInt(d["cols"]) ?? 80,
                                     rows: jsonInt(d["rows"]) ?? 24,
                                     colorRows: TileInk.decode(d["color"]))
            }
            paintedFromCache = true
            liveListSeen = false       // rows are HEARSAY until a refresh lands
            authenticated = true       // optimistic; a real 401 flips it back
            checkingAuth = false
        } else {
            checkingAuth = true
        }
        await refreshSessions(silent: true)
        checkingAuth = false
    }

    /// Whether anything could plausibly authenticate a refresh: the session
    /// cookie or a saved password. Gates the optimistic cache paint.
    private var hasAnyCredential: Bool {
        if let url = baseURL,
           HTTPCookieStorage.shared.cookies(for: url)?
               .contains(where: { $0.name == "tunnel_session" }) == true { return true }
        return Keychain.read(account: normalizedServerURL) != nil
    }

    /// Sign out for real: the cookie is what keeps you in, so dropping only
    /// the flag would let the next launch walk straight back in. Also drops
    /// the saved password, and the badge and quick actions — both leak session
    /// names to anyone holding the phone, which is precisely who you signed
    /// out for.
    /// Persist the wall's stores. Throttled: refreshes tick every few
    /// seconds, and rewriting an unchanged 50 KB file that often is churn.
    /// The first save after a cache paint goes immediately — it's the one
    /// replacing stale data.
    private func maybeSaveCache() {
        let force = paintedFromCache
        paintedFromCache = false
        guard force || Date().timeIntervalSince(lastCacheSaveAt) > 20 else { return }
        lastCacheSaveAt = Date()
        FleetCache.save(.init(sessions: lastRawSessions,
                              previews: previews,
                              screens: screensRaw,
                              folders: lastRawFolders))
    }

    func signOut() {
        FleetCache.delete()
        lastRawSessions = []
        lastRawFolders = []
        folders = []
        screensRaw = [:]
        if let url = baseURL {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        Keychain.delete(account: normalizedServerURL)
        seenBells = [:]          // stale baselines would silence a new account's first bell
        sessions = []
        previews = [:]
        // Everything below belongs to the account being left. lastKnown in
        // particular is not just clutter: it holds names, taglines and working
        // directories, and it is what renders a session that ended while you
        // were reading it — so a stale entry could show one server's session
        // details after signing into another.
        lastKnown = [:]
        openSession = nil
        requestedSession = nil
        lastError = nil
        actionError = nil
        authenticated = false
        authEpoch += 1
        HopNotifier.shared.reset()
        QuickActions.clear()
        clearSpotlight()
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
#if DEBUG
        // The cache probes' tourniquet: with this set, NO refresh runs — not
        // bootstrap's, not the periodic tick's. Gating only the bootstrap
        // call was a bug the gone-probe caught: the 5s tick refreshed the
        // wall live and OVERWROTE the cache mid-test.
        if ProcessInfo.processInfo.environment["HOP_DEV_CACHE_ONLY"] == "1" {
            checkingAuth = false
            return
        }
#endif
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
#if DEBUG
            HopSceneDelegate.mark("refresh status=\(http.statusCode) json=\(isJSON) hadCookie=\(hadSessionCookie)")
#endif
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
                if let fresh = rebaselinedMarker(existing: seen[key],
                                                 bellSeq: jsonInt(s["bellSeq"]) ?? 0) {
                    seen[key] = fresh
                    seeded = true
                }
            }
            // Drop markers for sessions that no longer exist. hop encourages
            // killing and recreating sessions, so without this the store grows
            // for the life of the install — and a name that comes back gets a
            // silent baseline from rebaselinedMarker anyway, which is what a
            // session this device has never seen should get.
            let live = Set(raw.compactMap { ($0["internalName"] as? String) ?? ($0["name"] as? String) })
            let pruned = seen.filter { live.contains($0.key) }
            if seeded || pruned.count != seen.count { seenBells = pruned }
            // HOP_DEV_ATTENTION=1 forces the first session into the attention
            // state: otherwise the design of the thing the app is FOR can only
            // be reviewed by waiting for an agent to ring. DEBUG-only — it
            // fakes app state, which has no place in a shipping build.
#if DEBUG
            // The first ALERTABLE session, not raw.first: the fleet reorders by
            // activity, and when a port or parked session drifts to the top,
            // forcing "attention" onto it counts for nothing (wanting excludes
            // both) — which made a test that relies on this flag flake with
            // the fleet's mood.
            if ProcessInfo.processInfo.environment["HOP_DEV_ATTENTION"] == "1",
               let first = raw.first(where: {
                   ($0["type"] as? String) != "port" && (($0["parked"] as? Bool) ?? false) == false
               }),
               let key = (first["internalName"] as? String) ?? (first["name"] as? String) {
                seen[key] = (jsonInt(first["bellSeq"]) ?? 0) - 1   // -1 is fine: any bellSeq beats it
            }
#endif
            sessions = raw.compactMap { HopSession(json: $0, seenBellSeq: seen) }
                .sorted { ($0.attention ? 1 : 0, $0.lastActivityAt) > ($1.attention ? 1 : 0, $1.lastActivityAt) }
            let rawFolders = (obj["folders"] as? [[String: Any]]) ?? []
            let parsedFolders = rawFolders.compactMap(HopFolder.init(json:))
            if folders != parsedFolders { folders = parsedFolders }
            lastRawFolders = rawFolders
            lastRawSessions = raw
            liveListSeen = true
            maybeSaveCache()
            publishFleetSnapshot()
            publishSpotlight()
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
            screens = screens.filter { alive.contains($0.key) }
            screensRaw = screensRaw.filter { alive.contains($0.key) }
            // Watching a session counts as seeing its bells: keep the marker
            // current so backing out doesn't leave a stale attention dot, and
            // never banner the terminal that's on screen.
            if let open = watching, let shown = sessions.first(where: { $0.internalName == open }),
               seenBells[open] != shown.bellSeq {
                markSeen(shown)
            }
            await HopNotifier.shared.report(attention: alertable(sessions, openSession: watching),
                                            known: alive) {
                [weak self] session in await self?.notificationSnippet(for: session)
            }
            QuickActions.publish(sessions)
            Logger(subsystem: "io.zhoulab.hop.spike", category: "model")
                .info("refresh: \(self.sessions.count) sessions, wanting \(self.sessions.filter { $0.attention && !$0.isPort && !$0.parked }.count)")
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
        // Origin is DECLARED, not inferred (hop2 18f86ce): undeclared
        // Bearer-token callers default to agent now. Everything this app
        // does is a human's act — say so, on every write.
        req.setValue("user", forHTTPHeaderField: "x-hop-actor")
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        actionError = nil        // this attempt replaces the last one's verdict
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
                actionError = (obj?["error"] as? String) ?? "Request failed"
            }
            return ok
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// cwd is optional and verified live: the daemon honours it (probed with
    /// a scratch session that landed in the requested directory), and omitting
    /// it keeps the daemon's default — the two cases the sheet offers.
    func createSession(name: String, cwd: String? = nil) async -> Bool {
        var body: [String: Any] = ["name": name, "type": "terminal"]
        if let cwd { body["cwd"] = cwd }
        return await post("api/sessions", body)
    }
    func renameSession(_ s: HopSession, to newName: String) async -> Bool {
        await post("api/sessions/rename", ["oldName": s.name, "newName": newName])
    }
    /// The tagline is "what this session is FOR" — shown under every name,
    /// in tile footers and on the widget. Agents set it via the API; now the
    /// phone can too. Empty clears it. Refresh so it propagates immediately.
    func setTagline(_ s: HopSession, to tagline: String) async -> Bool {
        let ok = await post("api/sessions/tagline",
                            ["internalName": s.internalName, "tagline": tagline])
        if ok { await refreshSessions(silent: true) }
        return ok
    }
    func setAgentAccess(_ s: HopSession, allowed: Bool) async -> Bool {
        await post("api/sessions/agent-permission", ["internalName": s.internalName, "allowed": allowed])
    }
    /// The widget's copy of the fleet. Reload only when the glanceable facts
    /// changed — WidgetKit budgets timeline reloads, and burning the budget
    /// on every 2-second poll would leave none for the changes that matter.
    private var lastSnapshotRows: [FleetSnapshot.Row] = []
    /// Raw JSON mirrors of what the wall renders, kept only to feed
    /// FleetCache — persisting the daemon's own JSON means the load path
    /// re-runs the exact live parsers and can never drift from them.
    private var lastRawSessions: [[String: Any]] = []
    private var lastRawFolders: [[String: Any]] = []
    private var screensRaw: [String: [String: Any]] = [:]
    private var lastCacheSaveAt = Date.distantPast
    /// True once this launch painted from cache — the first live refresh
    /// is the one that replaces it, so it always saves.
    private var paintedFromCache = false
    /// False while the visible list is cache hearsay; true once a live
    /// refresh has confirmed it. Attaching trusts a confirmed list but
    /// VERIFIES against a cached one — a cached row may be dead, and
    /// attaching to a dead-but-remembered name resurrects it daemon-side.
    private(set) var liveListSeen = true
    private func publishFleetSnapshot() {
        let browsable = sessions.filter { !$0.isPort && !$0.parked }
        let rows = browsable.prefix(4).map {
            FleetSnapshot.Row(internalName: $0.internalName,
                              name: $0.name, attention: $0.attention,
                              live: $0.live,
                              tagline: $0.tagline.isEmpty ? $0.shortCwd : $0.tagline)
        }
        let snap = FleetSnapshot(updatedAt: Date(),
                                 wanting: browsable.filter(\.attention).count,
                                 total: browsable.count,
                                 rows: Array(rows))
        snap.save()
        if rows != lastSnapshotRows {
            lastSnapshotRows = Array(rows)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The fleet in the system Spotlight index: search a session's name from
    /// the Home Screen and land in it. Re-donated only when names/taglines
    /// change — the index outlives the process, so idle polls need not touch
    /// it. Sign-out must clear it: session names on a signed-out phone are
    /// exactly what signOut() promises to remove.
    private var lastSpotlightKey = 0
    private func publishSpotlight() {
        let entries = spotlightEntries(sessions)
        var hasher = Hasher()
        for e in entries { hasher.combine(e.id); hasher.combine(e.title); hasher.combine(e.description) }
        let key = hasher.finalize()
        guard key != lastSpotlightKey else { return }
        lastSpotlightKey = key
        // The CS types are not Sendable; the String tuples are. Build the
        // items INSIDE the detached task so nothing non-Sendable crosses the
        // boundary — this was three strict-mode warnings, all mine.
        Task.detached(priority: .utility) {
            let items = entries.map { e in
                let attrs = CSSearchableItemAttributeSet(contentType: .item)
                attrs.title = e.title
                attrs.contentDescription = e.description
                attrs.keywords = ["hop", "terminal", e.title]
                return CSSearchableItem(uniqueIdentifier: e.id,
                                        domainIdentifier: "io.zhoulab.hop.sessions",
                                        attributeSet: attrs)
            }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: ["io.zhoulab.hop.sessions"])
            try? await index.indexSearchableItems(items)
        }
    }

    func clearSpotlight() {
        lastSpotlightKey = 0
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: ["io.zhoulab.hop.sessions"])
    }

    /// Parking is "not part of my working set right now", not "gone" — the
    /// session keeps running, it just leaves the browse list (and stays
    /// searchable). The refresh makes the change visible immediately instead
    /// of on the next poll.
    func setParked(_ s: HopSession, parked: Bool) async -> Bool {
        await setParked(internalName: s.internalName, parked: parked)
    }

    /// By name, for callers that never held a session object — the
    /// notification action parks from the lock screen.
    func setParked(internalName: String, parked: Bool) async -> Bool {
        let ok = await post("api/sessions/park",
                            ["internalName": internalName, "parked": parked])
        if ok { await refreshSessions(silent: true) }
        return ok
    }

    /// Opening a parked session IS unparking it — the same rule hop's own
    /// switcher follows. You went looking for it and opened it, so it is back
    /// in the working set, on every client rather than just this one.
    /// Best-effort: a failure leaves it parked, which is what it already was.
    func unpark(_ s: HopSession) async {
        guard s.parked else { return }
        _ = await setParked(s, parked: false)
    }

    /// Fork: a NEW session in the source's cwd; a recorded claude source
    /// resumes its history under a fresh conversation id (hop2 f6e6852).
    /// Returns the fork's internalName so the caller can open it.
    func forkSession(_ internalName: String) async -> String? {
        guard let url = baseURL?.appendingPathComponent("api/sessions/fork") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("user", forHTTPHeaderField: "x-hop-actor")   // same declaration as post()
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["internalName": internalName])
        actionError = nil
        do {
            let (data, resp) = try await urlSession.data(for: req)
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 500),
                  let fork = obj?["internalName"] as? String else {
                actionError = (obj?["error"] as? String) ?? "Fork failed"
                return nil
            }
            await refreshSessions(silent: true)
            return fork
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    /// File a session into a folder (nil = unfiled). The daemon owns the
    /// structure; this is the same POST the web's drag performs.
    func moveSession(_ internalName: String, toFolder folderId: String?) async -> Bool {
        var body: [String: Any] = ["internalName": internalName]
        if let folderId { body["folderId"] = folderId }
        return await post("api/sessions/move", body)
    }

    func createFolder(named name: String) async -> Bool {
        await post("api/folders", ["name": name])
    }

    /// Teardown-only today (probes clean up after themselves); the UI
    /// deliberately doesn't expose deletion — folders are shared structure.
    func deleteFolder(id: String) async -> Bool {
        await post("api/folders/delete", ["id": id])
    }

    /// Refile a session between You and Agents (the web sheet's "Move to
    /// user/agent sessions"). Origin is a filing decision, not a fact about
    /// the creator — hop lets you correct it.
    func setOrigin(_ internalName: String, createdBy: String) async -> Bool {
        await post("api/sessions/origin",
                   ["internalName": internalName, "createdBy": createdBy])
    }

    func killSession(_ s: HopSession) async -> Bool {
        await post("api/sessions/delete", ["internalName": s.internalName])
    }

    /// Fetch screen previews for the sessions the user can actually see.
    /// Mirrors the web switcher: bounded set, only while the list is open.
    func refreshPreviews(for names: [String]) async {
        // Same guard the session refresh carries, and it matters more here: a
        // preview IS terminal output. Without it, a fetch still in flight when
        // someone signs out lands afterwards and puts the previous account's
        // screen contents back into the store.
        let epoch = authEpoch
        await withTaskGroup(of: (String, String?).self) { group in
            // Sixteen, and the caller CAPS the visible head's share of it:
            // every budget below the wall's live-cell count has produced the
            // same starvation twice (marker logs showed a ~16-cell head
            // eating all twelve slots, so off-screen names never fetched).
            // The daemon renders a preview in ~1ms, so sixteen is cheap and
            // warms a 21-session fleet in two or three polls.
            for name in names.prefix(16) {
                group.addTask { [weak self] in
                    guard let self else { return (name, nil) }
                    return (name, await self.fetchPreview(name))
                }
            }
            for await (name, text) in group {
                guard epoch == authEpoch else { return }   // signed out mid-flight
                if let text, !text.isEmpty, previews[name] != text { previews[name] = text }
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
        let epoch = authEpoch
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
        // Search snippets are session output too, and this request outlives a
        // sign-out easily — it has a ten-second timeout.
        guard epoch == authEpoch else { return [] }
        return raw.compactMap { m in
            guard let internalName = m["internalName"] as? String else { return nil }
            return ContentMatch(internalName: internalName,
                                name: (m["name"] as? String) ?? internalName,
                                snippet: (m["snippet"] as? String) ?? "")
        }
    }

    /// The last meaningful line of a session's screen, for a notification body.
    /// Prefers the cached preview; fetches one otherwise, since a session that
    /// just rang is often NOT among the handful whose previews are polled.
    private func notificationSnippet(for session: HopSession) async -> String? {
        // ?? can't wrap an async call in its autoclosure — take the cached
        // preview if there is one, otherwise go and get one.
        let text: String?
        if let cached = previews[session.internalName] {
            text = cached
        } else {
            text = await fetchPreview(session.internalName)
        }
        guard let text else { return nil }
        return notificationLine(from: text)
    }

    /// One fetch feeds both stores: /preview returns the WHOLE screen as plain
    /// text plus its grid dimensions — the rows take their three meaningful
    /// lines from it, the tiles take all of it. No second endpoint, no ANSI
    /// stripping (the first tile attempt used /screen, whose output is escape
    /// sequences meant for a terminal, and rendered them as literal "[38;2m"
    /// confetti).
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
        let sp = ScreenPreview(text: text,
                               cols: jsonInt(obj["cols"]) ?? 80,
                               rows: jsonInt(obj["rows"]) ?? 24,
                               colorRows: TileInk.decode(obj["color"]))
        // Same screen → no write → no re-render. The text comparison
        // short-circuits the colour-rows one for the common idle case.
        if screens[internalName] != sp {
            screens[internalName] = sp
            var rawScreen: [String: Any] = ["text": text,
                                            "cols": jsonInt(obj["cols"]) ?? 80,
                                            "rows": jsonInt(obj["rows"]) ?? 24]
            if let color = obj["color"] { rawScreen["color"] = color }
            screensRaw[internalName] = rawScreen
        }
        return Self.meaningfulTail(of: text, lines: 3)
    }

    /// The last few lines that actually say something. A TUI's final lines are
    /// its own chrome — Claude's composer box, rule lines, the "bypass
    /// permissions" hint — so a naive tail shows every session as identical
    /// box-drawing. Skip chrome and keep real content.
    nonisolated static func meaningfulTail(of screen: String, lines wanted: Int) -> String {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        return meaningfulTailIndices(of: screen, lines: wanted)
            .map { String(lines[$0]).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    /// Index-based twin of meaningfulTail, so the COLOURED render can style
    /// exactly the rows the plain one would pick — the row indices are the
    /// contract between the text screen and its colour report.
    nonisolated static func meaningfulTailIndices(of screen: String, lines wanted: Int) -> [Int] {
        let boxChars = CharacterSet(charactersIn: "─│╭╮╰╯┌┐└┘├┤┬┴┼━┃▏▕▁▔█▀▄· ")
        let noise = ["bypass permissions", "esc to interrupt", "shift+tab to cycle",
                     "? for shortcuts", "ctrl+c to"]
        let kept = screen.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { _, raw in
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                if noise.contains(where: { lower.contains($0) }) { return false }
                // Prompt-only lines ("❯", "> ") carry no information.
                if line.count <= 2 { return false }
                // Mostly box-drawing => chrome.
                let boxCount = line.unicodeScalars.filter { boxChars.contains($0) }.count
                return Double(boxCount) / Double(line.unicodeScalars.count) < 0.6
            }
            .map(\.offset)
        return Array(kept.suffix(wanted))
    }

    /// Every session seen this launch. A session that ends while you're
    /// reading it drops out of `sessions` on the next refresh, and the
    /// navigation destination then had nothing to render — the screen went
    /// blank and took the final output with it. Falling back to the last known
    /// value keeps the terminal (and its "[session ended]" line) on screen.
    private(set) var lastKnown: [String: HopSession] = [:]

    /// What the app means by "a session" everywhere the user can see: port
    /// forwards are rows in hop's model but not terminals you open.
    var terminalSessions: [HopSession] { sessions.filter { !$0.isPort } }

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

    /// Mark by name+seq, for paths that never hold a HopSession — notably the
    /// background notification handler, which has only what the notification
    /// carried.
    func markSeen(internalName: String, bellSeq: Int) {
        var seen = seenBells
        seen[internalName] = max(seen[internalName] ?? 0, bellSeq)
        seenBells = seen
        HopNotifier.shared.clear(internalName)
    }

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

struct HopFolder: Identifiable, Equatable {
    let id: String
    let name: String
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let name = json["name"] as? String, !name.isEmpty else { return nil }
        self.id = id
        self.name = name
    }
}

struct HopSession: Identifiable {
    let name: String
    let internalName: String
    let cwd: String
    let foregroundProcess: String
    let lastActivityAt: Double

    /// The web wall's "producing output right now" signal, natively: the
    /// dot gets a sonar pulse while this is true.
    var busy: Bool {
        sessionBusy(lastActivityAt: lastActivityAt,
                    now: Date().timeIntervalSince1970)
    }
    let bellSeq: Int
    let live: Bool
    let isPort: Bool
    let attention: Bool
    let createdBy: String
    let tagline: String
    let agentPermitted: Bool
    /// A client is on this session's PTY right now — the desk's browser, the
    /// CLI, another phone. Presence at wall distance.
    let attached: Bool
    /// Jian's own filing (server-owned folders); nil = unfiled.
    let folderId: String?
    /// Hidden from the browsing list while still running. hop's word for "not
    /// part of my working set right now", and the phone honouring it is the
    /// whole point — a session parked from the desk that keeps appearing in
    /// your pocket has not been parked.
    let parked: Bool
    /// Parked AND stopped, but the daemon pre-wrote a restore plan, so opening
    /// it resumes the conversation rather than starting a new one.
    let archived: Bool
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
        attached = (json["attached"] as? Bool) ?? false
        // Both are `true` or absent — the daemon omits them rather than
        // sending false, so a missing key means "no".
        parked = (json["parked"] as? Bool) ?? false
        archived = (json["archived"] as? Bool) ?? false
        createdBy = (json["createdBy"] as? String) ?? "user"
        tagline = (json["tagline"] as? String) ?? ""
        folderId = json["folderId"] as? String
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

/// One session's whole rendered screen, for a switcher tile. Equatable so
/// the fetch can SKIP the store write when nothing changed — a @Published
/// dict mutation re-renders every visible tile, and an idle fleet was
/// rebuilding a dozen AttributedStrings every two seconds to draw the same
/// pixels.
struct ScreenPreview: Equatable {
    let text: String
    let cols: Int
    let rows: Int
    /// Styled runs per row (TileInk). Empty when the daemon has no colour
    /// for this session — the tile falls back to plain text.
    let colorRows: [[ColorRun]]
}
