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
        // The badge is the whole point of a home-screen app: how many sessions
        // want you, visible without opening anything. It tracks the live count
        // (not a running total), so reading a session drops it on the next
        // refresh. Silently ignored until notifications are authorized.
        UNUserNotificationCenter.current().setBadgeCount(sessions.count)
        guard enabled else { return }
        for s in sessions {
            guard s.attention, (notified[s.internalName] ?? -1) < s.bellSeq else { continue }
            notified[s.internalName] = s.bellSeq
            let content = UNMutableNotificationContent()
            content.title = s.name
            content.body = s.tagline.isEmpty ? "Session wants your attention" : s.tagline
            content.sound = .default
            // A waiting agent is what time-sensitive exists for. NOTE: this
            // currently degrades to .active on device — the wildcard team
            // provisioning profile drops the time-sensitive entitlement with
            // no build warning at all (verified via codesign -d
            // --entitlements). It starts working the moment the App ID carries
            // the capability; no code change needed. relevanceScore works
            // regardless and floats a bell to the top of a summary.
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
            content.userInfo = ["session": s.internalName]
            content.threadIdentifier = s.internalName   // group per session
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(s.internalName)-\(s.bellSeq)",
                                      content: content, trigger: nil))
        }
    }

    /// Signing out: drop the badge, everything delivered, and the per-session
    /// bell markers — otherwise the next account inherits this one's idea of
    /// what has already been seen, and its first real bell stays silent.
    func reset() {
        notified = [:]
        UNUserNotificationCenter.current().setBadgeCount(0)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Clear a session's pending notifications once the user is looking at it,
    /// and drop the badge by that session immediately rather than waiting out
    /// the poll interval.
    func clear(_ internalName: String) {
        let notified = enabled
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let mine = delivered.filter {
                ($0.request.content.userInfo["session"] as? String) == internalName
            }
            if !mine.isEmpty {
                UNUserNotificationCenter.current()
                    .removeDeliveredNotifications(withIdentifiers: mine.map(\.request.identifier))
            }
            // Recount from what's left. Only meaningful when notifications are
            // on — with them off there's nothing delivered to count, and the
            // next refresh sets the badge from live attention instead.
            guard notified else { return }
            let others = Set(delivered
                .compactMap { $0.request.content.userInfo["session"] as? String }
                .filter { $0 != internalName })
            UNUserNotificationCenter.current().setBadgeCount(others.count)
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
