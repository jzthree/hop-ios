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

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await QuickActions.handle(shortcutItem)
        return true
    }
}

final class HopAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = HopSceneDelegate.self
        return config
    }
}
