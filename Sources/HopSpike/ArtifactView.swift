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
    @State private var slowLoad = false
    @State private var loadFailure: String?
    @State private var retryToken = 0
    @State private var loadStage = ""
    /// A fetched copy of the published FILE, waiting for the Files exporter.
    @State private var exporting: ExportFile?
    @State private var exportError: String?

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
    /// Images and media leave the viewer its tap and swipe; a web page keeps
    /// every touch for itself.
    private var ownsGestures: Bool { isImage || isNativeMedia || (item.isServer && !item.serverLive) || url == nil }

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
                            // Video is immersive: get the bar out of the
                            // picture once playback is under way.
                            .task(id: url) {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation(.easeInOut(duration: 0.25)) { chromeHidden = true }
                            }
                    } else if isImage {
                        // Native, zoomable: an image in a web view is a
                        // page ABOUT an image. Pinch, pan, double-tap.
                        ArtifactImageView(url: url, loading: $loading)
                    } else {
                        ArtifactWebView(url: url, loading: $loading,
                                        topInset: chromeHidden ? 0 : barHeight,
                                        retry: retryToken,
                                        onFailure: { loadFailure = $0 },
                                        onStage: { loadStage = $0 })
                    }
                } else {
                    ContentUnavailableView("Can't open this view", systemImage: "questionmark.folder")
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .contentShape(Rectangle())
            // Tap to hide the bar, and a horizontal swipe to page between
            // results — but only over images and media. Over a web page both
            // sat ON TOP of the page: a sideways pan across a wide diagram or
            // table paged to the next result instead, and taps on the page's
            // own controls toggled the bar (probe, 2026-11-01). There the ▲▼
            // buttons page and the bar's ︿ hides it.
            .gesture(TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.18)) { chromeHidden.toggle() }
            }, including: ownsGestures ? .all : .subviews)
            .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                guard canPage, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                page(v.translation.width < 0 ? 1 : -1)
            }, including: ownsGestures ? .all : .subviews)

            if !chromeHidden {
                bar
                    .background(GeometryReader { g in
                        Color.clear.onAppear { barHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in barHeight = h }
                    })
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // The way back, ALWAYS. Tapping the content is meant to bring
                // the bar (and its Back button) back — but a WKWebView (rendered
                // markdown/CSV/JSON) swallows that tap, so once the bar hid you
                // were stuck in the viewer with no exit (Jian). This handle is a
                // SwiftUI view layered ABOVE the content, so its tap always
                // lands; it also gives immersive reading an honest affordance
                // instead of an invisible tap target.
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { chromeHidden = false }
                    } label: {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .padding(.top, topSafe + 2)
                            .padding(.bottom, 5)
                            .background(Color.hopPill.opacity(0.45))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show controls")
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
            }
            if loading && !isNativeMedia {
                VStack(spacing: 14) {
                    ProgressView().tint(.hopGlow)
                    if !isImage, !loadStage.isEmpty {
                        Text(loadStage).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityIdentifier("viewer-stage")
                    }
                    // A load that has not arrived in 12s is not going to on
                    // its own often enough to just keep spinning at you.
                    if slowLoad {
                        Button("Retry") { retry() }.buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(slowLoad)
                .task(id: "\(retryToken)|\(viewing.index)") {
                    slowLoad = false
                    try? await Task.sleep(for: .seconds(12))
                    if !Task.isCancelled, loading { withAnimation { slowLoad = true } }
                }
            } else if let loadFailure, !isNativeMedia {
                ContentUnavailableView {
                    Label("Couldn't load this view", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadFailure)
                } actions: {
                    Button("Retry") { retry() }.buttonStyle(.bordered)
                }
                .background(Color.hopSurface)
            }
        }
        .statusBarHidden(chromeHidden)
        // The cover's root must claim the whole screen: without this the
        // presented view is laid out inside the presenter's safe area, and
        // the bar sits below a black band that belongs to nobody.
        .ignoresSafeArea()
        .background(GeometryReader { g in
            Color.clear.onAppear { topSafe = g.safeAreaInsets.top }
                .onChange(of: g.safeAreaInsets.top) { _, t in topSafe = t }
        })
        // Looking at it IS reading it: mark the shown view seen so the strip's
        // unread accent clears — on open and on every page (a no-op for a bare
        // single-URL open, which carries no session/name to key on).
        .onAppear { ViewSeen.markItemSeen(item) }
        .onChange(of: viewing.index) { _, _ in ViewSeen.markItemSeen(item) }
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
            // An explicit way to hide the bar. Tapping the content does it
            // for pages and images, but a video's native player takes every
            // tap for its own controls — so over video the bar could never be
            // hidden (Jian: "when playing video from hop view I cannot hide
            // the top bar"). The pull-down handle brings it back.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { chromeHidden = true }
            } label: {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Hide controls")
            Menu {
                if let url {
                    // The FILE, not a link: the daemon's ?download=1 serves the
                    // published bytes under their real name (md/csv/json raw,
                    // not the rendered page); the system exporter offers
                    // Files, iCloud, and any provider (Jian: "I should be able
                    // to download a hop view item from the UI").
                    if !item.isServer {
                        Button { Task { await downloadForExport() } } label: {
                            Label("Save to Files…", systemImage: "arrow.down.doc")
                        }
                    }
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
            .sheet(item: $exporting) { file in
                DocumentExporter(url: file.url).ignoresSafeArea()
            }
            .alert("Couldn't download", isPresented: Binding(get: { exportError != nil },
                                                             set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "") }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.top, topSafe)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(Color.hopPill)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .strokeBorder(Color.hopLine(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 5)
    }

    private func retry() {
        loadFailure = nil
        slowLoad = false
        loading = true
        retryToken += 1
    }

    private func page(_ step: Int) {
        let next = viewing.index + step
        guard viewing.items.indices.contains(next) else { return }
        loading = true
        loadFailure = nil
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
    /// The floating preview plays silently and loops, with no controls.
    var muted = false
    var showsControls = true
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if showsControls {
                VideoPlayer(player: player)
            } else {
                PlayerLayerView(player: player)
            }
        }
        .background(Color.black)
        .task {
            guard player == nil else { return }
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
            let fresh = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            fresh.isMuted = muted
            if !showsControls {
                // Loop the silent preview.
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                       object: fresh.currentItem, queue: .main) { _ in
                    fresh.seek(to: .zero); fresh.play()
                }
            }
            player = fresh
            fresh.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// A bare AVPlayerLayer: video with no controls and no tap handling.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: LayerView, context: Context) { v.playerLayer.player = player }
}

struct ArtifactWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    /// The bar's height, so the page starts BELOW it: an inset, not a
    /// frame, so a chrome-hidden read still uses the whole screen and the
    /// page merely scrolls up under the top edge.
    var topInset: CGFloat = 0
    /// False for the floating preview: a WKWebView's own scroll view ignores
    /// SwiftUI's allowsHitTesting and stole the card's drag on device
    /// (Jian: "the scrolling gesture conflicts with dragging").
    var interactive = true
    /// Bumped by the viewer's Retry button.
    var retry = 0
    var onFailure: ((String) -> Void)? = nil
    /// Where the load is, in words ("Downloading 1.2 of 4.4 MB") — a spinner
    /// alone could never say what it was waiting for.
    var onStage: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(loading: $loading)
        c.onFailure = onFailure
        c.onStage = onStage
        return c
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// Documents the host serves as one self-contained page. The app fetches
    /// these itself and hands WebKit the bytes (see Coordinator.start).
    /// Everything else — PDFs, live servers — stays WebKit's to load.
    static func fetchesNatively(_ url: URL) -> Bool {
        guard url.path.hasPrefix("/view/") else { return false }
        var p = url.path
        if p.hasSuffix("/inline") { p.removeLast("/inline".count) }
        return ["html", "htm", "md", "markdown", "csv", "tsv", "json", "txt", "log"]
            .contains((p as NSString).pathExtension.lowercased())
    }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        if !interactive {
            web.isUserInteractionEnabled = false
            web.scrollView.isScrollEnabled = false
        }
        // hop's own surface under the page, not WebKit's white — the white
        // flash between open and first paint read as a different app.
        web.isOpaque = false
        web.backgroundColor = .hopSurface
        web.scrollView.backgroundColor = .hopSurface
        web.underPageBackgroundColor = UIColor(Color.hopSurface)
        // The app's session cookie, copied into the web view's store BEFORE
        // the load — the artifact lives behind the same auth as everything
        // else, and a cookieless load would render the login page instead of
        // the file. setCookie is async; loading first was a race the login
        // page won (same lesson as the digest's SPA-fallback surprise).
        context.coordinator.retries = retry
        context.coordinator.start(url, in: web)
        return web
    }

    /// Load `url` once the session cookie is in the web view's store — but
    /// never wait on the store forever. setCookie's completion sometimes
    /// never fires (a WebKit quirk with a fresh data store), and the viewer
    /// then sat on its spinner with nothing requested at all (Jian: "hop view
    /// html still broken often stuck with the spinning animation"). The
    /// cookie also rides on the request itself, so the document is
    /// authenticated even when the store loses the race.
    /// Fire and forget: the page's own requests (images beside it, a refresh)
    /// need the session cookie in WebKit's store.
    static func seedCookies(for url: URL, in web: WKWebView) {
        let store = web.configuration.websiteDataStore.httpCookieStore
        for c in HTTPCookieStorage.shared.cookies(for: url) ?? [] where c.name == "tunnel_session" {
            store.setCookie(c)
        }
    }

    static func load(_ url: URL, into web: WKWebView) {
        let cookies = (HTTPCookieStorage.shared.cookies(for: url) ?? []).filter { $0.name == "tunnel_session" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        HTTPCookie.requestHeaderFields(with: cookies).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        var fired = false
        let go = { [weak web] in
            guard !fired else { return }
            fired = true
            web?.load(req)
        }
        let store = web.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for c in cookies {
            group.enter()
            store.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main, execute: go)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: go)
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
        // Paging swaps the URL under the same view. Compared against what was
        // ASKED for, never web.url: that one moves on its own (a redirect, a
        // page's replaceState, a link followed) and is nil until a load
        // starts, and every mismatch restarted the load on the next SwiftUI
        // pass — each start bringing the spinner back.
        let c = context.coordinator
        c.onFailure = onFailure
        c.onStage = onStage
        if c.requested != url || c.retries != retry {
            c.retries = retry
            c.start(url, in: uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var loading: Bool
        var onFailure: ((String) -> Void)?
        var onStage: ((String) -> Void)?
        var retries = 0
        private(set) var requested: URL?
        private var fetch: Task<Void, Never>?
        private var watchdog: Task<Void, Never>?
        private var crashReloads = 0
        private var stageText = ""
        init(loading: Binding<Bool>) { _loading = loading }

        func stop() {
            fetch?.cancel(); fetch = nil
            watchdog?.cancel(); watchdog = nil
        }

        /// One load per request. An HTML result is fetched by the APP, on the
        /// same URLSession everything else in hop rides, and handed to WebKit
        /// as bytes: the spinner then has a real status code, real progress
        /// and a real error, where a load inside WebKit's network process can
        /// go silent (Jian: "endless spinner", from every way in, on the
        /// phone only). WebKit still gets the cookie, for what the page
        /// itself asks for.
        func start(_ url: URL, in web: WKWebView) {
            stop()
            requested = url
            loading = true
            guard ArtifactWebView.fetchesNatively(url) else {
                stage("Opening")
                ArtifactWebView.load(url, into: web)
                armWatchdog(seconds: 35, web)
                return
            }
            stage("Requesting")
            ArtifactWebView.seedCookies(for: url, in: web)
            fetch = Task { [weak self, weak web] in
                let tap = ViewFetchTap()
                var req = URLRequest(url: url)
                req.timeoutInterval = 30    // of silence, not of a whole download
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let meter = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard let text = tap.progressText else { continue }
                        self?.stage(text)
                    }
                }
                defer { meter.cancel() }
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req, delegate: tap)
                    guard !Task.isCancelled, let self, let web, self.requested == url else { return }
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        self.fail(status == 404 ? "This view is no longer published." : "The host answered \(status).")
                        return
                    }
                    self.fetch = nil
                    self.stage("Rendering")
                    web.load(data, mimeType: resp.mimeType ?? "text/html",
                             characterEncodingName: resp.textEncodingName ?? "utf-8",
                             baseURL: resp.url ?? url)
                    self.armWatchdog(seconds: 12, web)
                } catch {
                    guard !Task.isCancelled, let self, self.requested == url else { return }
                    self.fail(error.localizedDescription)
                }
            }
        }

        private func stage(_ text: String) {
            guard text != stageText else { return }
            stageText = text
            KBLog.record("viewer: \(text)")
            onStage?(text)
        }

        private func fail(_ message: String) {
            stop()
            loading = false
            KBLog.record("viewer failed at '\(stageText)': \(message)")
            onFailure?(message)
        }

        /// No page after this long is a failure with a Retry, not a spinner.
        private func armWatchdog(seconds: Int, _ web: WKWebView) {
            watchdog?.cancel()
            let at = stageText
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.fail("WebKit never started showing the page (stuck at: \(at)).")
            }
        }

        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { loading = true }
        // The spinner goes when the page starts ARRIVING, not when every
        // subresource has: a report pulling Google Fonts or a CDN script
        // over a phone link held didFinish back long after it was readable.
        func webView(_ w: WKWebView, didCommit n: WKNavigation!) { arrived() }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { arrived(); crashReloads = 0 }
        private func arrived() {
            watchdog?.cancel(); watchdog = nil
            loading = false
            stage("Shown")
        }
        // A heavy page (some views are tens of MB) can take WebKit's content
        // process down; no navigation callback follows, so the spinner was
        // left up over a blank page. Fetch it again once, then say so.
        func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
            KBLog.record("viewer content process terminated (reloads=\(crashReloads))")
            if crashReloads < 1, let requested {
                crashReloads += 1
                start(requested, in: w)
            } else {
                fail("This page is too heavy for the phone to show.")
            }
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { failed(e) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { failed(e) }
        private func failed(_ e: Error) {
            // A superseded load (paging, Retry) reports "cancelled": not a
            // failure, and the load that replaced it owns the spinner.
            if (e as NSError).code == NSURLErrorCancelled {
                if fetch == nil, watchdog == nil { loading = false }
                return
            }
            fail(e.localizedDescription)
        }
    }
}

/// Hands back the URLSessionTask so its bytes can be read while it runs.
final class ViewFetchTap: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }
    var progressText: String? {
        guard let t = lock.withLock({ task }), t.countOfBytesReceived > 0 else { return nil }
        let got = ByteCountFormatter.string(fromByteCount: t.countOfBytesReceived, countStyle: .file)
        guard t.countOfBytesExpectedToReceive > 0 else { return "Downloading \(got)" }
        let all = ByteCountFormatter.string(fromByteCount: t.countOfBytesExpectedToReceive, countStyle: .file)
        return "Downloading \(got) of \(all)"
    }
}

/// A temp copy of a published file, ready for the system exporter.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// "Save to Files": UIDocumentPickerViewController in export mode. `asCopy`
/// so the temp file is copied out and can be cleaned up afterwards.
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
}

extension ArtifactSheet {
    /// Fetch the published bytes (the daemon's ?download=1 form, authenticated
    /// the same way the viewer's own loads are) into a temp file bearing the
    /// item's real name, then hand it to the exporter.
    @MainActor func downloadForExport() async {
        let raw = viewing.serverURL.isEmpty ? item.path : viewing.serverURL + item.path
        guard var comps = URLComponents(string: raw) else { exportError = "Bad link"; return }
        comps.queryItems = (comps.queryItems ?? []).filter { $0.name != "download" }
            + [URLQueryItem(name: "download", value: "1")]
        guard let dl = comps.url else { exportError = "Bad link"; return }
        var req = URLRequest(url: dl)
        req.timeoutInterval = 60
        let cookies = HTTPCookieStorage.shared.cookies(for: dl) ?? []
        req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                exportError = "Server returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)"; return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hop-export", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = item.name.isEmpty ? "view" : item.name
            let file = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try data.write(to: file, options: .atomic)
            exporting = ExportFile(url: file)
        } catch {
            exportError = error.localizedDescription
        }
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
    @State private var query = ""
    @State private var kind: ViewKind = .all
    /// Cleared from inside: a session's own Views open filtered to it with
    /// "all" one tap away (the web's session chip and its ×).
    @State private var scoped: String?
    @State private var scopeSet = false
    @State private var seenTick = 0
    @Environment(\.dismiss) private var dismiss

    // Results are mostly visual, and a list of filenames hid that (hop web's
    // Views redesign, 2026-10-31): a gallery of cards by day, the way a lab
    // notebook reads — figures as their own thumbnails, documents set like a
    // manuscript's first page. A card opens the reader, which pages through
    // what the filters show.
    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if inScope.isEmpty {
                    ContentUnavailableView(
                        "Nothing published yet",
                        systemImage: "tray",
                        description: Text("When an agent runs `hop view` on a plot, a report or a PDF, it lands here, by day."))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            filterBar
                            if shown.isEmpty {
                                Text(query.isEmpty ? "Nothing of this kind." : "Nothing here matches “\(query)”.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.top, 40)
                            }
                            ForEach(days, id: \.day) { d in
                                Section {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                                        ForEach(d.rows) { card($0) }
                                    }
                                } header: {
                                    HStack(spacing: 6) {
                                        Text(d.day.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .tracking(0.8)
                                        Text("\(d.rows.count)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                                prompt: "Title, file or session")
                }
            }
            .background(Color.hopSurface)
            .navigationTitle(scoped.map { "Views · \(nameFor($0))" } ?? "Views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $viewing, onDismiss: { seenTick += 1 }) { v in ArtifactSheet(viewing: v) }
            .task {
                if !scopeSet { scoped = onlySession; scopeSet = true }
                await load()
            }
            .refreshable { await load() }
        }
    }

    // MARK: gallery

    private var inScope: [ArtifactItem] {
        guard let scoped else { return items }
        return items.filter { $0.session == scoped }
    }

    /// What the kind filter and the search let through, in manifest order
    /// (newest first) — also what the reader pages through.
    private var shown: [ArtifactItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return inScope.filter { i in
            (kind == .all || ViewKind.of(i) == kind)
                && (q.isEmpty || i.label.lowercased().contains(q) || i.name.lowercased().contains(q)
                    || nameFor(i.session).lowercased().contains(q))
        }
    }

    private var days: [(day: String, rows: [ArtifactItem])] {
        var order: [String] = []
        var buckets: [String: [ArtifactItem]] = [:]
        let now = Date()
        for i in shown {
            let d = viewDayLabel(i.mtime, now: now)
            if buckets[d] == nil { order.append(d) }
            buckets[d, default: []].append(i)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let s = scoped {
                    Button { withAnimation { scoped = nil } } label: {
                        HStack(spacing: 4) {
                            Text(nameFor(s)).lineLimit(1)
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.hopPurple.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Only \(nameFor(s)). Tap for every session.")
                }
                ForEach(ViewKind.allCases, id: \.self) { k in
                    let n = k == .all ? inScope.count : inScope.filter { ViewKind.of($0) == k }.count
                    if k == .all || n > 0 {
                        Button { withAnimation(.easeOut(duration: 0.15)) { kind = k } } label: {
                            HStack(spacing: 4) {
                                Text(k.label)
                                Text("\(n)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .font(.footnote.weight(kind == k ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(kind == k ? Color.hopLine(0.12) : Color.hopLine(0.04), in: Capsule())
                            .foregroundStyle(kind == k ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kind == k ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    private func card(_ item: ArtifactItem) -> some View {
        let _ = seenTick
        let fresh = !item.isServer && ViewSeen.itemState(item) != .seen
        return Button {
            let list = shown
            if let i = list.firstIndex(where: { $0.id == item.id }) {
                viewing = ArtifactViewing(items: list, index: i, serverURL: serverURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    thumb(item)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.hopLine(0.10), lineWidth: 0.5))
                        .shadow(color: Color.hopShadow.opacity(0.5), radius: 4, y: 2)
                    if fresh {
                        Circle().fill(Color.hopSpark)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                            .padding(7)
                            .accessibilityLabel("New")
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.footnote.weight(fresh ? .bold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(meta(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !item.isServer {
                Button(role: .destructive) {
                    Task { await remove(item) }
                } label: { Label("Delete view", systemImage: "trash") }
            }
        }
    }

    private func meta(_ item: ArtifactItem) -> String {
        if item.isServer { return item.serverLive ? "live server" : "server gone" }
        let time = Date(timeIntervalSince1970: item.mtime).formatted(.relative(presentation: .named))
        return scoped == nil ? "\(nameFor(item.session)) · \(time)" : time
    }

    @ViewBuilder private func thumb(_ item: ArtifactItem) -> some View {
        if !item.isServer, ViewKind.isImage(item.name),
           let url = URL(string: serverURL + item.path.replacingOccurrences(
                of: "/inline", with: "", options: [.anchored, .backwards]) + "/thumb") {
            ViewThumb(url: url)
        } else {
            DocCard(item: item)
        }
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
    ownServerURL(link, serverURL: serverURL) != nil
}

private let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

/// The link as this hop serves it, or nil when it is someone else's. A
/// `hop view` link on the daemon's loopback address (the CLI prints that
/// when no tunnel is up) is this hop's too — hop web's parseViewLink rule —
/// and is rewritten onto the server the phone reaches; Safari on the phone
/// cannot reach the Mac's 127.0.0.1. Punctuation dragged in from markdown
/// after the view path ("…/inline**", "…/inline).") is dropped: the host
/// served its SPA for those, so the reader showed hop instead of the file.
func ownServerURL(_ link: String, serverURL: String) -> URL? {
    guard var comps = URLComponents(string: link), let host = comps.host?.lowercased(),
          let server = URL(string: serverURL), let own = server.host?.lowercased() else { return nil }
    let isView = comps.path.hasPrefix("/view/")
    guard host == own || (isView && loopbackHosts.contains(host)) else { return nil }
    if host != own {
        comps.scheme = server.scheme
        comps.host = server.host
        comps.port = server.port
    }
    if isView {
        comps.path = trimTrailingPunctuation(comps.path)   // keeps a balanced "(1)"
    }
    return comps.url
}


/// `.sheet(item:)` needs Identifiable; a URL is its own identity.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Views gallery pieces (hop web's ViewsPanel)

/// The gallery's kind filters, as the web names them.
enum ViewKind: CaseIterable {
    case all, figures, docs, pages, live
    var label: String {
        switch self {
        case .all: return "All"
        case .figures: return "Figures"
        case .docs: return "Docs"
        case .pages: return "Pages"
        case .live: return "Live"
        }
    }
    private static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
    static func isImage(_ name: String) -> Bool { ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(ext(name)) }
    static func of(_ i: ArtifactItem) -> ViewKind {
        if i.isServer { return .live }
        let e = ext(i.name)
        if isImage(i.name) || ["mp4", "mov", "webm", "m4v", "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus"].contains(e) {
            return .figures
        }
        if e == "html" || e == "htm" { return .pages }
        return .docs
    }
    /// A short type tag, set in mono like the web's (emoji glyphs differ too
    /// much to carry meaning).
    static func tag(_ i: ArtifactItem) -> String {
        if i.isServer { return "LIVE" }
        let e = ext(i.name)
        switch e {
        case "csv", "tsv": return "TBL"
        case "pdf": return "PDF"
        case "md", "markdown": return "MD"
        case "html", "htm": return "WEB"
        case "txt", "log", "json": return "TXT"
        case "mp4", "mov", "webm", "m4v": return "VID"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus": return "AUD"
        default: return isImage(i.name) ? "IMG" : "FILE"
        }
    }
}

/// The day a result belongs to, as a notebook would head it.
func viewDayLabel(_ mtime: Double, now: Date = Date()) -> String {
    let cal = Calendar.current
    let d = Date(timeIntervalSince1970: mtime)
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
    if days <= 0 { return "Today" }
    if days == 1 { return "Yesterday" }
    if days < 7 { return d.formatted(.dateTime.weekday(.wide)) }
    let sameYear = cal.component(.year, from: d) == cal.component(.year, from: now)
    return sameYear ? d.formatted(.dateTime.month(.wide).day()) : d.formatted(.dateTime.month(.wide).day().year())
}

/// A figure's card: the host's small JPEG (`/view/…/thumb`), never the
/// full image — a gallery of plots must not pull megabytes through the
/// tunnel. Cached for the app's life.
struct ViewThumb: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.gray)
            }
        }
        .task(id: url) {
            if let hit = Self.cache.object(forKey: url as NSURL) { image = hit; return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: url) ?? [])
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) {
                Self.cache.setObject(img, forKey: url as NSURL)
                image = img
            } else {
                failed = true
            }
        }
    }
}

/// A document's card, set like a manuscript's first page: its kind tag, the
/// title in a serif on ruled paper, an edge in its kind's colour (docs
/// violet, pages cyan, live servers green).
struct DocCard: View {
    let item: ArtifactItem
    @Environment(\.colorScheme) private var scheme

    private var edge: Color {
        switch ViewKind.of(item) {
        case .pages: return Color(hex: 0x06b6d4)
        case .live: return item.serverLive ? .hopLive : .secondary
        default: return Color(hex: 0x7c3aed)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            edge.opacity(0.75).frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                Text(ViewKind.tag(item))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.hopLine(0.06), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
                Text(item.label)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.hopInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Capsule().fill(Color.hopLine(0.12)).frame(width: 46, height: 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(scheme == .dark ? Color.hopRaised : Color(hex: 0xfdfcf8))
    }
}
