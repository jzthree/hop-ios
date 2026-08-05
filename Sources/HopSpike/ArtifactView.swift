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
