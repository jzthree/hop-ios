import UIKit
import os

// Home Screen quick actions: long-press the hop icon and go straight into the
// session that wants you — the pair to the badge. The badge says how many; this
// says which, and skips the list entirely.
//
// SwiftUI's App lifecycle has no hook for these: a cold-launch quick action
// arrives in scene(_:willConnectTo:options:) and a warm one in
// windowScene(_:performActionFor:), both scene-delegate methods. So the app
// supplies a scene delegate that ONLY observes — it never makes a window, and
// SwiftUI's WindowGroup still owns the UI.
enum QuickActions {
    static let sessionKey = "session"

    /// Rebuilt after every refresh: sessions wanting attention first (the
    /// reason you'd long-press at all), then the most recent. iOS shows at
    /// most four, so asking for more just wastes them.
    @MainActor private static var published: [String] = []

    @MainActor
    static func publish(_ sessions: [HopSession]) {
        let ordered = sessions.prefix(4)         // already attention-first, then recent
        // The list refreshes every 5s; handing SpringBoard an identical array
        // twelve times a minute is pure IPC for nothing.
        let signature = ordered.map { "\($0.internalName)|\($0.attention)|\($0.tagline)" }
        guard signature != published else { return }
        published = signature
        UIApplication.shared.shortcutItems = ordered.map { s in
            UIApplicationShortcutItem(
                type: "io.zhoulab.hop.spike.session",
                localizedTitle: s.name,
                localizedSubtitle: s.attention ? "Wants your attention"
                    : (s.tagline.isEmpty ? s.shortCwd : s.tagline),
                icon: UIApplicationShortcutIcon(systemImageName: s.attention ? "bell.badge" : "terminal"),
                userInfo: [sessionKey: s.internalName as NSString])
        }
        // Quick actions live in SpringBoard, so there is no way to verify them
        // from a screenshot or a test — this log line is the only evidence the
        // publish actually happened.
        Logger(subsystem: "io.zhoulab.hop.spike", category: "quickactions")
            .info("published \(UIApplication.shared.shortcutItems?.count ?? 0) quick actions")
    }

    @MainActor
    static func clear() {
        published = []
        UIApplication.shared.shortcutItems = []
    }

    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) {
        guard let name = item.userInfo?[sessionKey] as? String else { return }
        AppModel.shared.requestedSession = name
    }
}

final class HopSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // Cold launch. The list isn't loaded yet; requestedSession is read once
        // the session arrives, so setting it this early is fine.
        if let item = connectionOptions.shortcutItem {
            Task { @MainActor in QuickActions.handle(item) }
        }
    }

    /// The completion-handler form, not the async one. UIKit calls this on the
    /// main thread, so @MainActor is simply the truth — whereas the async
    /// variant has to send a non-Sendable UIApplicationShortcutItem across an
    /// actor boundary, which Swift 6 rejects however it's written.
    @MainActor
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActions.handle(shortcutItem)
        completionHandler(true)
    }
}

/// APNs registration. The entitlement is live now that the App ID is explicit
/// and has Push enabled — a wildcard App ID cannot carry `aps-environment`,
/// which is why this was blocked for so long.
///
/// This is the CLIENT half only: it obtains the device token and keeps it
/// where diagnostics can show it. Actually delivering a push needs a daemon
/// endpoint to register the token against and a send-on-bell path in hop, both
/// of which are hop2 changes.
@MainActor
final class PushRegistry: ObservableObject {
    static let shared = PushRegistry()
    @Published private(set) var deviceToken: String?
    @Published private(set) var failure: String?

    func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func received(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        failure = nil
        Logger(subsystem: "io.zhoulab.hop.spike", category: "push")
            .info("APNs token \(self.deviceToken?.prefix(12) ?? "")… (\(token.count) bytes)")
    }

    func failed(_ error: Error) {
        failure = error.localizedDescription
        Logger(subsystem: "io.zhoulab.hop.spike", category: "push")
            .error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

final class HopAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in PushRegistry.shared.received(token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistry.shared.failed(error) }
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = HopSceneDelegate.self
        return config
    }
}
