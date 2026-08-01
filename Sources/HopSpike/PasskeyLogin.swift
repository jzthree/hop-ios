import SwiftUI
import WebKit

// Sign in with the passkey you already registered in hop web — Face ID instead
// of a password and a 6-digit code.
//
// WHY A WEB VIEW, when the daemon already speaks WebAuthn (/api/passkeys/*,
// @simplewebauthn/server) and iOS has a native passkey API:
// ASAuthorizationPlatformPublicKeyCredentialProvider requires the Associated
// Domains entitlement (`webcredentials:<host>`), which requires a provisioning
// profile carrying that capability — i.e. the Apple Developer account that has
// been empty since day one — AND the host must serve
// /.well-known/apple-app-site-association naming this app, which hop does not.
// Both are recorded in PLAN; when they land, this file's UI stays and its
// middle is replaced by the native sheet.
//
// A WKWebView reaches the same platform authenticator (passkeys work in
// WKWebView on iOS 16+) against the same rpID, so it uses the SAME passkey —
// nothing new to enroll. On success the daemon sets `tunnel_session`, the one
// cookie the whole app authenticates with, and we copy it into
// HTTPCookieStorage.shared, which is exactly what a password login leaves
// behind. No credential is stored by this app and none passes through it.
struct PasskeyLoginSheet: View {
    let serverURL: String
    /// Called once the session cookie is in the app's shared storage.
    var onAuthenticated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    var body: some View {
        NavigationStack {
            PasskeyWebView(serverURL: serverURL) {
                // Guard against the poller firing twice on the same success.
                guard !done else { return }
                done = true
                dismiss()
                onAuthenticated()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct PasskeyWebView: UIViewRepresentable {
    let serverURL: String
    let onCookie: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCookie: onCookie) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // The DEFAULT (persistent) store, not an ephemeral one: passkey
        // ceremonies need a real origin with real storage, and the cookie we
        // are here to collect must survive the redirect that sets it.
        cfg.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        if let url = URL(string: serverURL) {
            web.load(URLRequest(url: url))
        }
        context.coordinator.start(web: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookie: () -> Void
        private var poll: Task<Void, Never>?
        private var fired = false

        init(onCookie: @escaping () -> Void) {
            self.onCookie = onCookie
        }

        /// Poll rather than watch a navigation: the passkey login is an XHR,
        /// so the page may never navigate — the only reliable evidence that
        /// the ceremony succeeded is the cookie itself appearing.
        func start(web: WKWebView) {
            poll?.cancel()
            poll = Task { @MainActor [weak self, weak web] in
                for _ in 0..<600 {                     // ~2 minutes
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, !self.fired, let web else { return }
                    let cookies = await web.configuration.websiteDataStore
                        .httpCookieStore.allCookies()
                    guard let session = cookies.first(where: { $0.name == "tunnel_session" })
                    else { continue }
                    self.fired = true
                    // The app authenticates from HTTPCookieStorage.shared —
                    // the same place a password login's Set-Cookie lands.
                    HTTPCookieStorage.shared.setCookie(session)
                    self.onCookie()
                    return
                }
            }
        }

        func stop() {
            poll?.cancel()
            poll = nil
        }
    }
}
