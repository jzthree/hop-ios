import SwiftUI
import WebKit
import AVKit

// The in-app viewer for `hop view` artifacts — HTML, PDFs, images published
// by an agent behind hop's auth. Safari cannot open these (it has no hop
// session); this sheet carries the app's own cookie into a WKWebView, whose
// engine renders all three natively. Any link that points at the user's own
// hop server routes here instead of leaving the app. Video and audio go to
// a native AVPlayer instead — see ArtifactPlayerView for why.

/// The artifact's real file name. Views URLs end in a literal `/inline`
/// segment (it keeps the extension out of the URL for edge caches), so the
/// name that carries the extension is the component BEFORE the last one.
private func artifactFileName(_ url: URL) -> String {
    let parts = url.pathComponents
    let raw = (parts.last == "inline" && parts.count >= 2) ? parts[parts.count - 2]
        : url.lastPathComponent
    return raw.removingPercentEncoding ?? raw
}

/// What the viewer was opened ON: a specific row plus its neighbors, so it
/// can page through a session's results without going back to the list.
/// A bare URL (a tapped link, an older caller) is a one-item pager.
struct ArtifactViewing: Identifiable {
    let items: [ArtifactItem]
    let index: Int
    let serverURL: String
    var id: String { items[index].path }

    static func single(url: URL) -> ArtifactViewing {
        let name = artifactFileName(url)
        let item = ArtifactItem(session: "", name: name, title: "",
                                path: url.path, isServer: false, bytes: 0, mtime: 0)
        return ArtifactViewing(items: [item], index: 0,
                               serverURL: url.scheme.map { "\($0)://\(url.host ?? "")" } ?? "")
    }
}

/// The result viewer, in hop's own chrome — the same pill-bar language as
/// the terminal, on the same dark surface. It was a stock system sheet with a
/// white web view flashing under a filename title; a result an agent handed
/// over deserves to open in the app it was handed to, not in a borrowed one.
struct ArtifactSheet: View {
    @State var viewing: ArtifactViewing
    @Environment(\.dismiss) private var dismiss
    /// Measured, not looked up: windowTopInset() reads the KEY window's
    /// safe area, and a full-screen cover is presented in a window of its
    /// own — the first cut sat the bar 60pt below the island in a black
    /// void. GeometryReader on the cover's own safe area is the truth here.
    @State private var topSafe: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    /// Full-bleed for reading: one tap on the content hides the bar, one
    /// tap brings it back — the way every reader app treats its chrome.
    @State private var chromeHidden = false
    @State private var loading = true

    init(url: URL) { _viewing = State(initialValue: .single(url: url)) }
    init(viewing: ArtifactViewing) { _viewing = State(initialValue: viewing) }

    private var item: ArtifactItem { viewing.items[viewing.index] }
    private var url: URL? {
        // A bare-URL open carries an absolute path already; a manifest item
        // carries the daemon path and needs the server prepended.
        // String concatenation, NOT appendingPathComponent: that API
        // percent-encodes the slashes inside a multi-segment path, so a live
        // server's target ("/s/room-roomcms/admin/…") became one bogus
        // component, missed the proxy route, and hit the SPA fallback — the
        // viewer opened the hop WALL instead of the server. The manifest
        // paths are already URL paths; use them as such.
        let base: URL?
        if viewing.serverURL.isEmpty { base = URL(string: item.path) }
        else { base = URL(string: viewing.serverURL + item.path) }
        // The app is force-dark; the daemon's rendered pages (markdown, CSV,
        // JSON) follow the OS unless told otherwise, and on a light-mode
        // phone that put a white page inside a black app. Say dark.
        guard let base, ["md", "markdown", "csv", "tsv", "json"].contains(ext),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        comps.queryItems = (comps.queryItems ?? []).filter { $0.name != "theme" }
            + [URLQueryItem(name: "theme", value: "dark")]
        return comps.url
    }
    private var ext: String { (item.name as NSString).pathExtension.lowercased() }
    /// Containers AVPlayer actually decodes. webm deliberately stays in the
    /// web view — AVFoundation has no VP8/VP9, and a black native player is
    /// strictly worse than whatever WebKit can do with it.
    private var isNativeMedia: Bool {
        ["mp4", "m4v", "mov", "m4a", "mp3", "aac", "wav", "flac"].contains(ext)
    }
    private var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].contains(ext)
    }
    private var canPage: Bool { viewing.items.count > 1 }

    var body: some View {
        ZStack(alignment: .top) {
            Color.hopSurface.ignoresSafeArea()
            Group {
                if item.isServer && !item.serverLive {
                    ContentUnavailableView {
                        Label("Server gone", systemImage: "globe.badge.chevron.backward")
                    } description: {
                        Text("The session that served this has stopped. Re-run hop port in that session to bring it back.")
                    }
                } else if let url {
                    if isNativeMedia {
                        ArtifactPlayerView(url: url)
                    } else if isImage {
                        // Native, zoomable: an image in a web view is a
                        // page ABOUT an image. Pinch, pan, double-tap.
                        ArtifactImageView(url: url, loading: $loading)
                    } else {
                        ArtifactWebView(url: url, loading: $loading,
                                        topInset: chromeHidden ? 0 : barHeight)
                    }
                } else {
                    ContentUnavailableView("Can't open this view", systemImage: "questionmark.folder")
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { chromeHidden.toggle() }
            }
            // Page between a session's results with a horizontal swipe on
            // the content — the same gesture the terminal uses to switch
            // sessions, so it is already in the thumb.
            .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                guard canPage, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                page(v.translation.width < 0 ? 1 : -1)
            })

            if !chromeHidden {
                bar
                    .background(GeometryReader { g in
                        Color.clear.onAppear { barHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in barHeight = h }
                    })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if loading && !isNativeMedia {
                ProgressView().tint(.hopGlow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(chromeHidden)
        // The cover's root must claim the whole screen: without this the
        // presented view is laid out inside the presenter's safe area, and
        // the bar sits below a black band that belongs to nobody.
        .ignoresSafeArea()
        .background(GeometryReader { g in
            Color.clear.onAppear { topSafe = g.safeAreaInsets.top }
                .onChange(of: g.safeAreaInsets.top) { _, t in topSafe = t }
        })
    }

    /// The pill bar — the terminal's chrome, reused verbatim in shape: black,
    /// meeting the island, rounded at the bottom.
    private var bar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 56, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                // The filename earns a line only when the title is saying
                // the useful thing; and a pager says where you are.
                if !item.title.isEmpty || canPage {
                    Text([item.title.isEmpty ? "" : (item.name.removingPercentEncoding ?? item.name),
                          canPage ? "\(viewing.index + 1) of \(viewing.items.count)" : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if canPage {
                Button { page(-1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .disabled(viewing.index == 0)
                .accessibilityLabel("Previous view")
                Button { page(1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .disabled(viewing.index == viewing.items.count - 1)
                .accessibilityLabel("Next view")
            }
            Menu {
                if let url {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = url.absoluteString } label: {
                        Label("Copy link", systemImage: "link")
                    }
                    Button { UIApplication.shared.open(url) } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.top, topSafe)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(Color.hopIslandBlack)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 5)
    }

    private func page(_ step: Int) {
        let next = viewing.index + step
        guard viewing.items.indices.contains(next) else { return }
        loading = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) {
            viewing = ArtifactViewing(items: viewing.items, index: next, serverURL: viewing.serverURL)
        }
    }
}

/// A zoomable image: pinch, pan, double-tap to toggle 1x/2.5x. Native
/// because a raw image loaded into a web view is a page about an image —
/// tiny in a white corner, un-pinchable in the way that matters.
struct ArtifactImageView: View {
    let url: URL
    @Binding var loading: Bool
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { g in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(MagnificationGesture()
                            .onChanged { v in scale = max(1, min(6, lastScale * v)) }
                            .onEnded { _ in lastScale = scale; if scale == 1 { offset = .zero; lastOffset = .zero } })
                        .simultaneousGesture(DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset })
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                                else { scale = 2.5; lastScale = 2.5 }
                            }
                        }
                } else {
                    Color.clear
                }
            }
        }
        .task(id: url) {
            loading = true
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
            if let (data, _) = try? await URLSession.shared.data(for: req) {
                image = UIImage(data: data)
            }
            loading = false
        }
    }
}

/// Native playback for published video/audio. WKWebView could render these,
/// but AVPlayer gives scrubbing, fullscreen, AirPlay — and honest HDR: an
/// HLG/PQ test cut published for review renders with EDR here, which is the
/// entire point of publishing one. The session cookie rides on the asset via
/// AVURLAssetHTTPCookiesKey, exactly as the web view carries it, because the
/// media stack makes its own requests and inherits nothing from SwiftUI.
struct ArtifactPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .task {
                guard player == nil else { return }
                let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
                let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
                let fresh = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                player = fresh
                fresh.play()
            }
            .onDisappear { player?.pause() }
    }
}

struct ArtifactWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    /// The bar's height, so the page starts BELOW it: an inset, not a
    /// frame, so a chrome-hidden read still uses the whole screen and the
    /// page merely scrolls up under the top edge.
    var topInset: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        // hop's own surface under the page, not WebKit's white — the white
        // flash between open and first paint read as a different app.
        web.isOpaque = false
        web.backgroundColor = UIColor(Color.hopSurface)
        web.scrollView.backgroundColor = UIColor(Color.hopSurface)
        web.underPageBackgroundColor = UIColor(Color.hopSurface)
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

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Never let the system add its own top inset on top of ours: with
        // automatic adjustment the page carried BOTH the safe-area inset and
        // the bar inset, and opened with a band of surface above the h1.
        uiView.scrollView.contentInsetAdjustmentBehavior = .never
        if uiView.scrollView.contentInset.top != topInset {
            let wasAtTop = uiView.scrollView.contentOffset.y <= -uiView.scrollView.contentInset.top + 1
            uiView.scrollView.contentInset.top = topInset
            uiView.scrollView.verticalScrollIndicatorInsets.top = topInset
            if wasAtTop { uiView.scrollView.contentOffset.y = -topInset }
        }
        // Paging swaps the URL under the same view; reload only when it
        // actually changed, or every SwiftUI pass would restart the load.
        if uiView.url != url, !(uiView.isLoading && uiView.url == nil) {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let store = uiView.configuration.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            for c in cookies where c.name == "tunnel_session" {
                group.enter(); store.setCookie(c) { group.leave() }
            }
            group.notify(queue: .main) { [weak uiView] in
                if uiView?.url != url { uiView?.load(URLRequest(url: url)) }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var loading: Bool
        init(loading: Binding<Bool>) { _loading = loading }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { loading = true }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { loading = false }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { loading = false }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { loading = false }
    }
}

/// One published view, from the manifest hop view maintains.
struct ArtifactItem: Identifiable, Equatable {
    let session: String
    let name: String
    /// What the agent SAID it was handing over (`hop view --title`). Empty
    /// for anything published without one.
    let title: String
    let path: String
    /// A LIVE proxied localhost server rather than a stored file. It can stop
    /// working when the server does, which a file never does — worth saying
    /// on the row rather than letting a dead link look like a broken view.
    let isServer: Bool
    /// For a server row: whether the proxied session still EXISTS. A row
    /// whose session evaporated used to open the hop wall (proxy miss → SPA
    /// fallback) with no hint why; a dead door should look like one.
    var serverLive: Bool = true
    let bytes: Int
    let mtime: Double
    var id: String { path }

    /// Lead with the title: "ROC curve, new model vs baseline" is the reason
    /// to open this; "roc_curve.png" makes you open it to find out.
    var label: String {
        title.isEmpty ? (name.removingPercentEncoding ?? name) : title
    }

    var glyph: String {
        if isServer { return "globe" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
        case "html", "htm": return "safari"
        case "md", "markdown", "txt": return "doc.text"
        case "mp4", "mov", "webm": return "play.rectangle"
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
    /// Scope to ONE session's results. A result belongs to the conversation
    /// that produced it, and from inside that conversation the rest of the
    /// fleet's output is noise; nil keeps the fleet-wide folder.
    var onlySession: String? = nil
    @State private var items: [ArtifactItem] = []
    @State private var loaded = false
    @State private var viewing: ArtifactViewing?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing published yet",
                        systemImage: "tray",
                        description: Text("When an agent runs `hop view` on a plot, a report or a PDF, it lands here."))
                } else {
                    List {
                        ForEach(grouped, id: \.session) { group in
                            // Scoped to one session, the header would repeat
                            // the title bar.
                            Section(onlySession == nil ? nameFor(group.session) : "") {
                                ForEach(group.rows) { item in
                                    Button {
                                        // Open ON this row with its neighbors,
                                        // so the viewer can page the list.
                                        if let i = items.firstIndex(where: { $0.id == item.id }) {
                                            viewing = ArtifactViewing(items: items, index: i, serverURL: serverURL)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: item.glyph)
                                                .foregroundStyle(item.isServer
                                                                 ? (item.serverLive ? Color.hopAttention : Color.secondary)
                                                                 : Color.hopGlow)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.label)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                // The filename earns its place
                                                // only once a title is saying
                                                // the useful thing.
                                                // A server has no meaningful
                                                // size or filename to show —
                                                // it's a door, not a document.
                                                Text(item.isServer
                                                     ? (item.serverLive ? "live server · tap to open" : "server gone — no longer running")
                                                     : (item.title.isEmpty ? Self.stamp(item)
                                                        : "\(item.name.removingPercentEncoding ?? item.name) · \(Self.stamp(item))"))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    // Swipe-to-delete, the platform's own
                                    // gesture (Jian: "we should be able to
                                    // swipe to do something to the views").
                                    // Servers are doors, not files — nothing
                                    // to delete, so no action to offer.
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if !item.isServer {
                                            Button(role: .destructive) {
                                                Task { await remove(item) }
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                    }
                                    // Retraction, from the reading side. The
                                    // publisher has --rm; the human staring
                                    // at a stale or mistaken result had no
                                    // way to clear it. Servers are excluded —
                                    // their row dies with the server.
                                    .swipeActions(edge: .trailing) {
                                        if !item.isServer {
                                            Button(role: .destructive) {
                                                Task { await remove(item) }
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                    }
                                    .contextMenu {
                                        if !item.isServer {
                                            Button(role: .destructive) {
                                                Task { await remove(item) }
                                            } label: { Label("Delete view", systemImage: "trash") }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(onlySession.map { "Views · \(nameFor($0))" } ?? "Views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $viewing) { v in ArtifactSheet(viewing: v) }
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

    private func remove(_ item: ArtifactItem) async {
        if await deleteArtifact(serverURL: serverURL, urlSession: urlSession,
                                session: item.session, name: item.name) {
            withAnimation { items.removeAll { $0.id == item.id } }
        }
    }

    private func load() async {
        // /api/views is the same bytes as the legacy
        // /assets/view/manifest.json, under a name that says what it is; the
        // old path stays served for builds already on phones.
        guard let url = URL(string: serverURL)?
            .appendingPathComponent("api/views") else { loaded = true; return }
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
            if let only = onlySession, s != only { return nil }
            let server = (o["kind"] as? String) == "server"
            // Straight to the proxy for a server: the scan found a redirect
            // page, and bouncing the reader through it is a visible flash and
            // a wasted round trip on a phone link.
            let target = (o["target"] as? String) ?? ""
            return ArtifactItem(session: s, name: n,
                                title: (o["title"] as? String) ?? "",
                                path: server && !target.isEmpty ? target : p,
                                isServer: server,
                                serverLive: (o["live"] as? Bool) ?? true,
                                bytes: (o["bytes"] as? Int) ?? 0,
                                mtime: (o["mtime"] as? Double) ?? 0)
        }
    }
}

/// Unpublish one view — the daemon's DELETE /api/views, the same call the
/// web wall uses. Copies only: the source file the agent published from is
/// not hop's to delete, and a live server row is refused server-side.
func deleteArtifact(serverURL: String, urlSession: URLSession,
                    session: String, name: String) async -> Bool {
    guard let url = URL(string: serverURL)?.appendingPathComponent("api/views")
    else { return false }
    var req = URLRequest(url: url)
    req.httpMethod = "DELETE"
    req.timeoutInterval = 8
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: [
        "session": session, "name": name,
    ])
    guard let (_, resp) = try? await urlSession.data(for: req) else { return false }
    return (resp as? HTTPURLResponse)?.statusCode == 200
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
