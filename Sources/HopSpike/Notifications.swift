import UIKit
import os
import UserNotifications

// Bell notifications. A hop session rings BEL when it wants you (an agent
// finished, a job needs input); the daemon counts those into bellSeq. When a
// session's bellSeq passes what this device has seen, post a local
// notification — banners show even in the foreground, and tapping one opens
// that session. This is the local half; APNs (fires with the app closed) is
// the server-side follow-up.
/// File scope, not a static: a stored property's initializer cannot reference
/// the type it lives in.
private let notifiedBellsKey = "notifiedBells"

@MainActor
final class HopNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = HopNotifier()

    @Published var enabled: Bool = ProcessInfo.processInfo.environment["HOP_DEV_NOTIFY"] == "1"
        || UserDefaults.standard.bool(forKey: "notifyBells")
    /// Session the user tapped a notification for; the UI navigates to it.
    @Published var pendingOpen: String?

    /// internalName -> bellSeq already notified. PERSISTED: the contract this
    /// class advertises is "one bell, one notification", and an in-memory map
    /// only keeps that promise until the app is killed. A phone kills apps
    /// constantly, and every relaunch re-notified every session still waiting —
    /// bells you had already read and dismissed, arriving again.
    private var notified: [String: Int] =
        UserDefaults.standard.dictionary(forKey: notifiedBellsKey) as? [String: Int] ?? [:]

    /// The category that carries the Reply action. Registered once at launch:
    /// a notification without it shows no reply field, and the category has to
    /// exist BEFORE any notification referencing it is posted.
    static let bellCategory = "HOP_SESSION_BELL"

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: "HOP_REPLY", title: "Reply",
            options: [], textInputButtonTitle: "Send",
            textInputPlaceholder: "Answer this session…")
        // Parking from the banner is the other half of triage: "not now"
        // without unlocking anything, for the bell that can wait.
        let park = UNNotificationAction(
            identifier: "HOP_PARK", title: "Park",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "moon.zzz"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.bellCategory, actions: [reply, park],
                                   intentIdentifiers: [], options: [])
        ])
        // Enabled from a previous launch (or the dev flag) still needs the OS
        // grant — without it every post is silently dropped.
        if enabled {
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if !granted { enabled = false; return }
                // EVERY launch, not just the first opt-in. APNs tokens change
                // on reinstall, restore-from-backup and some iOS updates, and
                // Apple's guidance is to re-register each launch and refresh
                // the server's copy. Registering only on the toggle meant the
                // token silently went stale the moment the app was relaunched.
                PushRegistry.shared.register()
            }
        }
    }

    func setEnabled(_ on: Bool) async {
        if on {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            enabled = granted
            if !granted { return }
            // With permission in hand, ask APNs for a token too. Harmless if
            // the daemon can't use it yet; it means the moment the endpoint
            // exists, the token is already there.
            PushRegistry.shared.register()
        } else {
            enabled = false
        }
        UserDefaults.standard.set(enabled, forKey: "notifyBells")
    }

    /// Called after every session refresh with the sessions currently wanting
    /// attention. Dedupes per bellSeq so one bell is one notification.
    /// `snippet` returns what the session is actually SAYING right now. The
    /// body used to be the tagline — a description of what a session is for,
    /// which never changes and so never answers the only question a bell
    /// raises: what does it want? "Do you want me to proceed?" is worth
    /// waking a phone for; "Polish mobile client" is not.
    /// `known` is every session that still exists, so records for sessions
    /// that are gone don't accumulate on disk forever.
    func report(attention sessions: [HopSession], known: Set<String>,
                snippet: (HopSession) async -> String?) async {
        // The badge is the whole point of a home-screen app: how many sessions
        // want you, visible without opening anything. It tracks the live count
        // (not a running total), so reading a session drops it on the next
        // refresh. Silently ignored until notifications are authorized.
        // In an async context these resolve to the async overloads.
        try? await UNUserNotificationCenter.current().setBadgeCount(sessions.count)
        guard enabled else { return }
        for s in sessions {
            guard s.attention, shouldNotify(bellSeq: s.bellSeq,
                                            lastNotified: notified[s.internalName]) else { continue }
            let content = UNMutableNotificationContent()
            content.title = s.name
            let live = await snippet(s)
            content.body = live
                ?? (s.tagline.isEmpty ? "Session wants your attention" : s.tagline)
            // The tagline still rides along as the subtitle when there's a live
            // line to show: which session, and what it's for, without crowding
            // the part you actually read.
            if live != nil, !s.tagline.isEmpty { content.subtitle = s.tagline }
            content.sound = .default
            // A waiting agent is what time-sensitive exists for. It needs the
            // com.apple.developer.usernotifications.time-sensitive entitlement,
            // which the App ID can now carry (it's explicit, with Push enabled)
            // — add it to project.yml's entitlements block if Focus
            // breakthrough is wanted. relevanceScore works regardless and
            // floats a bell to the top of a summary.
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
            content.categoryIdentifier = Self.bellCategory
            // bellSeq travels with it so a reply handled in the background can
            // mark the session seen without fetching the list first.
            content.userInfo = ["session": s.internalName, "bellSeq": s.bellSeq]
            content.threadIdentifier = s.internalName   // group per session
            // Recorded as notified only once it HAS been, and never with
            // `try?`. Marking it first meant a refused notification was also a
            // permanently silenced one: the dedupe said "posted", so the next
            // poll skipped it and that bell was never shown at all. Failing to
            // tell someone an agent is waiting is this app's worst outcome, so
            // a failure retries five seconds later instead.
            do {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "\(s.internalName)-\(s.bellSeq)",
                                          content: content, trigger: nil))
                notified[s.internalName] = s.bellSeq
            } catch {
                Logger(subsystem: "io.zhoulab.hop.spike", category: "notify")
                    .error("bell refused for \(s.internalName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !known.isEmpty { notified = notified.filter { known.contains($0.key) } }
        UserDefaults.standard.set(notified, forKey: notifiedBellsKey)
    }

    /// Signing out: drop the badge, everything delivered, and the per-session
    /// bell markers — otherwise the next account inherits this one's idea of
    /// what has already been seen, and its first real bell stays silent.
    func reset() {
        notified = [:]
        UserDefaults.standard.removeObject(forKey: notifiedBellsKey)
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
        guard let name else { return }
        // Park from the banner: "not now", handled where the user is
        // standing. Parking IS attending to the bell — mark it seen, or the
        // badge nags about a session the user just put away.
        if response.actionIdentifier == "HOP_PARK" {
            _ = await AppModel.shared.setParked(internalName: name, parked: true)
            let seq = jsonInt(response.notification.request.content.userInfo["bellSeq"])
            await MainActor.run {
                AppModel.shared.markSeen(internalName: name, bellSeq: seq ?? 0)
            }
            return
        }
        // Typed a reply instead of tapping: answer the session where the user
        // is standing, rather than dragging them into the app to type one word.
        if let typed = (response as? UNTextInputNotificationResponse)?.userText,
           !typed.trimmingCharacters(in: .whitespaces).isEmpty {
            let ok = await QuickReply.send(typed, to: name, model: AppModel.shared)
            if ok {
                // Answering IS attending to it. Without this the session kept
                // its dot and its badge after you'd already dealt with it,
                // which is the app nagging about something you just handled.
                // Coerced, not cast. Today this userInfo is one we built, so
                // it holds an Int — but the same handler will receive APNs
                // payloads, and a number decoded from a push arrives as
                // NSNumber. `as? Int` yields nil for that, and the failure is
                // silent in the worst way: the reply sends, and the session
                // keeps its dot and its badge as though you had ignored it.
                let seq = jsonInt(response.notification.request.content.userInfo["bellSeq"])
                await MainActor.run {
                    AppModel.shared.markSeen(internalName: name, bellSeq: seq ?? 0)
                }
            } else {
                // Never leave someone believing an answer was delivered.
                let failed = UNMutableNotificationContent()
                failed.title = name
                failed.body = "Couldn't send that reply — open the session to check."
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "\(name)-reply-failed",
                                          content: failed, trigger: nil))
            }
            return
        }
        await MainActor.run { HopNotifier.shared.pendingOpen = name }
    }
}
