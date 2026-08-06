import SwiftUI
import WebKit

// The in-app viewer for `hop view` artifacts — HTML, PDFs, images published
// by an agent behind hop's auth. Safari cannot open these (it has no hop
// session); this sheet carries the app's own cookie into a WKWebView, whose
// engine renders all three natively. Any link that points at the user's own
// hop server routes here instead of leaving the app.
struct ArtifactSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArtifactWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent.removingPercentEncoding
                                 ?? url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }
}

struct ArtifactWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        // The app's session cookie, copied into the web view's store BEFORE
        // the load — the artifact lives behind the same auth as everything
        // else, and a cookieless load would render the login page instead of
        // the file. setCookie is async; loading first was a race the login
        // page won (same lesson as the digest's SPA-fallback surprise).
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let store = web.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for c in cookies where c.name == "tunnel_session" {
            group.enter()
            store.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main) { [weak web] in
            web?.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// One published artifact, from the manifest hop view maintains.
struct ArtifactItem: Identifiable, Equatable {
    let session: String
    let name: String
    let path: String
    let bytes: Int
    let mtime: Double
    var id: String { path }

    var glyph: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
        case "html", "htm": return "safari"
        default: return "doc"
        }
    }
}

/// The virtual folder: everything any agent has published with `hop view`,
/// fleet-wide, newest first, grouped by session. One manifest fetch — the
/// files themselves load lazily when a row is opened.
struct ArtifactsBrowser: View {
    let serverURL: String
    let urlSession: URLSession
    /// internalName → display name, same mapping the briefing uses.
    var nameFor: (String) -> String
    /// Scope to one session — the terminal's side panel. Fleet-wide when nil.
    var onlySession: String? = nil
    /// Live webservers (hop's port sessions): the daemon proxies
    /// /s/<name>/ to the server's localhost port behind the same cookie —
    /// a REAL running dev server in the viewer, not a file of it.
    var servers: [(name: String, internalName: String)] = []
    @State private var items: [ArtifactItem] = []
    @State private var loaded = false
    @State private var viewing: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty && servers.isEmpty {
                    ContentUnavailableView(
                        "Nothing published yet",
                        systemImage: "tray",
                        description: Text("When an agent runs `hop view` on a plot, a report or a PDF, it lands here."))
                } else {
                    List {
                        if !servers.isEmpty {
                            Section("Live servers") {
                                ForEach(servers, id: \.internalName) { srv in
                                    Button {
                                        if var u = URL(string: serverURL) {
                                            u.appendPathComponent("s/\(srv.internalName)/")
                                            viewing = u
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "globe")
                                                .foregroundStyle(Color.hopLive)
                                                .frame(width: 22)
                                            Text(srv.name)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(grouped, id: \.session) { group in
                            Section(nameFor(group.session)) {
                                ForEach(group.rows) { item in
                                    Button {
                                        if let u = URL(string: serverURL)?
                                            .appendingPathComponent(String(item.path.dropFirst())) {
                                            viewing = u
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: item.glyph)
                                                .foregroundStyle(Color.hopGlow)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.name.removingPercentEncoding ?? item.name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(Self.stamp(item))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(onlySession.map { nameFor($0) } ?? "Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $viewing) { url in ArtifactSheet(url: url) }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var grouped: [(session: String, rows: [ArtifactItem])] {
        // Newest-first sessions, newest-first rows — the manifest is already
        // time-sorted, so group order falls out of first appearance.
        var order: [String] = []
        var buckets: [String: [ArtifactItem]] = [:]
        for i in items {
            if buckets[i.session] == nil { order.append(i.session) }
            buckets[i.session, default: []].append(i)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private static func stamp(_ item: ArtifactItem) -> String {
        let date = Date(timeIntervalSince1970: item.mtime)
        let time = date.formatted(.relative(presentation: .named))
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.bytes),
                                            countStyle: .file)
        return "\(time) · \(size)"
    }

    private func load() async {
        guard let url = URL(string: serverURL)?
            .appendingPathComponent("assets/view/manifest.json") else { loaded = true; return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        defer { loaded = true }
        guard let (data, resp) = try? await urlSession.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["items"] as? [[String: Any]] else { return }
        items = raw.compactMap { o in
            guard let s = o["session"] as? String, let n = o["name"] as? String,
                  let p = o["path"] as? String else { return nil }
            return ArtifactItem(session: s, name: n, path: p,
                                bytes: (o["bytes"] as? Int) ?? 0,
                                mtime: (o["mtime"] as? Double) ?? 0)
        }
        if let only = onlySession { items = items.filter { $0.session == only } }
    }
}

/// Does this link point at the user's own hop server? Those open in-app —
/// Safari has no session and would show the login page.
func isOwnServerLink(_ link: String, serverURL: String) -> Bool {
    guard let u = URL(string: link), let host = u.host?.lowercased(),
          let server = URL(string: serverURL), let own = server.host?.lowercased()
    else { return false }
    return host == own
}


/// `.sheet(item:)` needs Identifiable; a URL is its own identity.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
