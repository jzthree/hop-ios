import UIKit
import UserNotifications

// Bell notifications. A hop session rings BEL when it wants you (an agent
// finished, a job needs input); the daemon counts those into bellSeq. When a
// session's bellSeq passes what this device has seen, post a local
// notification — banners show even in the foreground, and tapping one opens
// that session. This is the local half; APNs (fires with the app closed) is
// the server-side follow-up.
@MainActor
final class HopNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = HopNotifier()

    @Published var enabled: Bool = ProcessInfo.processInfo.environment["HOP_DEV_NOTIFY"] == "1"
        || UserDefaults.standard.bool(forKey: "notifyBells")
    /// Session the user tapped a notification for; the UI navigates to it.
    @Published var pendingOpen: String?

    private var notified: [String: Int] = [:]   // internalName -> bellSeq already notified

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        // Enabled from a previous launch (or the dev flag) still needs the OS
        // grant — without it every post is silently dropped.
        if enabled {
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if !granted { enabled = false }
            }
        }
    }

    func setEnabled(_ on: Bool) async {
        if on {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            enabled = granted
            if !granted { return }
        } else {
            enabled = false
        }
        UserDefaults.standard.set(enabled, forKey: "notifyBells")
    }

    /// Called after every session refresh with the sessions currently wanting
    /// attention. Dedupes per bellSeq so one bell is one notification.
    func report(attention sessions: [HopSession]) {
        guard enabled else { return }
        for s in sessions {
            guard s.attention, (notified[s.internalName] ?? -1) < s.bellSeq else { continue }
            notified[s.internalName] = s.bellSeq
            let content = UNMutableNotificationContent()
            content.title = s.name
            content.body = s.tagline.isEmpty ? "Session wants your attention" : s.tagline
            content.sound = .default
            content.userInfo = ["session": s.internalName]
            content.threadIdentifier = s.internalName   // group per session
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(s.internalName)-\(s.bellSeq)",
                                      content: content, trigger: nil))
        }
    }

    /// Clear a session's pending notifications once the user is looking at it.
    func clear(_ internalName: String) {
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { ($0.request.content.userInfo["session"] as? String) == internalName }
                .map(\.request.identifier)
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // Banner even when the app is open — the user may be in another session.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let name = response.notification.request.content.userInfo["session"] as? String
        await MainActor.run { if let name { HopNotifier.shared.pendingOpen = name } }
    }
}
