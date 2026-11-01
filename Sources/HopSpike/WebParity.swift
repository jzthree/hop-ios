import Foundation
import SwiftUI
import WebKit

// What hop web does that the phone did not: take a thread back from the
// Codex app (`hop recover --take`), agent accounts, folder renames, the
// directory completer, the update notice and the machine's desktop. Each is
// the web client's own daemon call (hay/apps/web/src), so the two stay one
// feature with two faces.

/// One of an agent's login roots on the host (`/api/agent-homes`).
struct AgentHome: Identifiable, Equatable {
    let dir: String
    let label: String
    let isDefault: Bool
    /// nil = the host could not ask.
    let loggedIn: Bool?
    let email: String?
    var id: String { dir }

    init?(json: [String: Any]) {
        guard let dir = json["dir"] as? String, let label = json["label"] as? String else { return nil }
        self.dir = dir
        self.label = label
        isDefault = (json["isDefault"] as? Bool) ?? false
        let login = json["login"] as? [String: Any]
        loggedIn = login?["loggedIn"] as? Bool
        email = login?["email"] as? String
    }

    /// "fable · a@b.org", "claude2 · logged out", or just the name — the
    /// web's describeAccount.
    var described: String {
        let name = isDefault ? "default" : label
        guard let loggedIn else { return name }
        if !loggedIn { return "\(name) · logged out" }
        return email.map { "\(name) · \($0)" } ?? name
    }
}

/// `/api/update`: the host's hop against the newest published.
struct HopUpdateInfo: Equatable {
    let current: String
    let latest: String
    let command: String
}

/// A directory the completer offers (`/api/fs/complete`).
struct DirEntry: Identifiable, Equatable {
    let name: String
    let path: String
    var id: String { path }
}

extension AppModel {
    func getObject(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 10) async -> [String: Any]? {
        guard let base = baseURL?.appendingPathComponent(path),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await urlSession.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The agents' accounts, keyed "claude" / "codex". Kept as is on failure
    /// (an older daemon simply never offers the switch).
    func loadAgentHomes() async {
        guard let obj = await getObject("api/agent-homes") else { return }
        var out: [String: [AgentHome]] = [:]
        for agent in ["claude", "codex"] {
            out[agent] = ((obj[agent] as? [[String: Any]]) ?? []).compactMap(AgentHome.init(json:))
        }
        if out != agentHomes { agentHomes = out }
    }

    func homes(for s: HopSession) -> [AgentHome] { agentHomes[s.agentApp] ?? [] }

    /// Move a session's agent to another account; returns the line to show.
    func switchAgentHome(_ s: HopSession, to home: AgentHome) async -> String {
        guard let obj = await postReturning("api/sessions/agent-home",
                                            ["name": s.internalName, "home": home.dir]) else {
            return actionError ?? "Switch failed"
        }
        await refreshSessions(silent: true)
        return (obj["restarted"] as? Bool) == true
            ? "\(s.name) now runs as \(home.label)"
            : "\(s.name) is set to \(home.label); it switches on its next start"
    }

    /// `hop recover --take`: quit the Codex app so it lets go of this
    /// session's thread, then resume it here. Returns the line to show.
    func takeFromCodexApp(_ s: HopSession) async -> String {
        guard let obj = await postReturning("api/codex/take", ["internalName": s.internalName]) else {
            return actionError ?? "Could not take the conversation back"
        }
        await refreshSessions(silent: true)
        let freed = (obj["freed"] as? Bool) == true
        let paused = (obj["paused"] as? [String]) ?? []
        let pausedNote = paused.isEmpty ? "" : " (paused app automation \(paused.map { "“\($0)”" }.joined(separator: ", ")))"
        if (obj["restarted"] as? Bool) == true {
            return "\(s.name) resumed here\(freed ? " — the Codex app let go" : "")\(pausedNote)"
        }
        let why = (obj["skipped"] as? String).map { ": \($0)" } ?? ""
        return "\(freed ? "The Codex app let go, but " : "")\(s.name) was not relaunched\(why)"
    }

    func renameFolder(id: String, to name: String) async -> Bool {
        let ok = await postReturning("api/folders/rename", ["id": id, "name": name]) != nil
        if ok { await refreshSessions(silent: true) }
        return ok
    }

    /// Directories on the HOST matching a partial path ("~/Code/ho"), and
    /// the host's home so "~" can be expanded before the create call.
    func completeDirectory(_ q: String) async -> (home: String?, entries: [DirEntry]) {
        guard let obj = await getObject("api/fs/complete", query: [URLQueryItem(name: "q", value: q)], timeout: 5),
              let entries = obj["entries"] as? [[String: Any]] else { return (nil, []) }
        return (obj["home"] as? String, entries.compactMap { e in
            guard let name = e["name"] as? String, let path = e["path"] as? String else { return nil }
            return DirEntry(name: name, path: path)
        })
    }

    /// nil unless a newer hop is published for the host.
    func fetchUpdateInfo() async -> HopUpdateInfo? {
        guard let obj = await getObject("api/update"),
              (obj["updateAvailable"] as? Bool) == true,
              let current = obj["current"] as? String, let latest = obj["latest"] as? String else { return nil }
        return HopUpdateInfo(current: current, latest: latest, command: (obj["command"] as? String) ?? "hop update")
    }

    /// True once `hop desktop` is set up and the VNC server answers.
    func desktopAvailable() async -> Bool {
        guard let obj = await getObject("api/desktop") else { return false }
        return (obj["enabled"] as? Bool) == true && (obj["reachable"] as? Bool) != false
    }
}

/// The machine's desktop (`hop desktop on`), full screen. noVNC is the
/// viewer, so this is hop web's own `?desktop=only` page in a web view —
/// the same sign-in box (Mac account or VNC password), fit and view-only
/// toggles. Its Close button posts "close" to the `hop` handler.
struct DesktopSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = URL(string: model.normalizedServerURL + "/?desktop=only") {
                DesktopWebView(url: url, loading: $loading) { dismiss() }
                    .ignoresSafeArea(edges: .bottom)
            }
            if loading { ProgressView().tint(.hopGlow) }
        }
    }
}

struct DesktopWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading, onClose: onClose) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "hop")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        ArtifactWebView.load(url, into: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // The handler retains the coordinator; and leaving must drop the VNC
        // connection, which loading nothing does.
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "hop")
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var loading: Bool
        let onClose: () -> Void
        init(loading: Binding<Bool>, onClose: @escaping () -> Void) { _loading = loading; self.onClose = onClose }
        func webView(_ w: WKWebView, didCommit n: WKNavigation!) { loading = false }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { loading = false }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { loading = false }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if (m.body as? String) == "close" { onClose() }
        }
    }
}
