import BackgroundTasks
import Foundation
import os

// Local notifications only fire while the app is running, so a bell rung while
// the phone is in a pocket was missed entirely. iOS background refresh closes
// most of that gap without any server work: when the system grants us a slot,
// poll /api/sessions and notify for anything that rang since this device last
// looked. (APNs remains the only way to be woken *immediately* with the app
// closed — that needs a daemon endpoint.)
enum BackgroundRefresh {
    static let identifier = "io.zhoulab.hop.spike.refresh"

    /// What happened last time we asked for a slot, and last time one was
    /// granted — both surfaced in Copy diagnostics.
    ///
    /// This exists because the feature spent its whole life invisible. Asking
    /// for a slot can fail permanently and silently (a missing identifier, the
    /// background mode absent, Background App Refresh switched off), and the
    /// only symptom is a phone that never tells you an agent rang — which
    /// looks exactly like no agent ringing. It cannot be answered from a
    /// simulator either: BGTaskScheduler is refused there outright.
    private(set) static var lastSchedule: String {
        get { UserDefaults.standard.string(forKey: "bgLastSchedule") ?? "never asked" }
        set { UserDefaults.standard.set(newValue, forKey: "bgLastSchedule") }
    }
    private(set) static var lastRun: String {
        get { UserDefaults.standard.string(forKey: "bgLastRun") ?? "never ran" }
        set { UserDefaults.standard.set(newValue, forKey: "bgLastRun") }
    }

    private static var stamp: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: Date())
    }

    static func register(model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(refresh, model: model)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // A floor, not a promise: iOS decides the real cadence from usage.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        let log = Logger(subsystem: "io.zhoulab.hop.spike", category: "background")
        do {
            try BGTaskScheduler.shared.submit(request)
            lastSchedule = "requested \(stamp)"
            log.info("background slot requested")
        } catch {
            // Swallowing this is how a feature ends up looking implemented and
            // never once running: an identifier missing from
            // BGTaskSchedulerPermittedIdentifiers, or a build without the
            // background mode, fails here EVERY time and silently. There is
            // nothing to show the user — they cannot act on it — but a phone
            // that never wakes should not also be silent about why.
            lastSchedule = "refused \(stamp) — \(error.localizedDescription)"
            log.error("background slot refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask, model: AppModel) {
        lastRun = "ran \(stamp)"     // the only proof iOS ever grants us one
        schedule()   // always queue the next one, successful or not
        let log = Logger(subsystem: "io.zhoulab.hop.spike", category: "background")

        // Completing a BGTask twice is a hard error — iOS logs "was completed
        // twice" and can stop granting slots at all. That's exactly what a slow
        // tunnel would cause here: the system expires the window while the
        // refresh is still in flight, the handler completes it, and then the
        // refresh finishes and completes it again. One completion wins.
        let once = OnceComplete(task: task, log: log)

        // Set BEFORE the work starts: an expiration arriving in that window
        // would otherwise find no handler.
        var work: Task<Void, Never>?
        task.expirationHandler = {
            work?.cancel()
            once.finish(success: false)
        }
        work = Task {
            await model.refreshSessions(silent: true)   // posts notifications itself
            once.finish(success: true)
        }
    }
}

/// Whichever of the two paths gets there first completes the task; the other
/// becomes a no-op.
private final class OnceComplete {
    private let lock = NSLock()
    private var done = false
    private let task: BGTask
    private let log: Logger

    init(task: BGTask, log: Logger) {
        self.task = task
        self.log = log
    }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        log.info("background refresh finished, success=\(success, privacy: .public)")
        task.setTaskCompleted(success: success)
    }
}
