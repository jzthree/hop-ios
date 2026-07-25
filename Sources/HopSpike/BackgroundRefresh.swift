import BackgroundTasks
import Foundation

// Local notifications only fire while the app is running, so a bell rung while
// the phone is in a pocket was missed entirely. iOS background refresh closes
// most of that gap without any server work: when the system grants us a slot,
// poll /api/sessions and notify for anything that rang since this device last
// looked. (APNs remains the only way to be woken *immediately* with the app
// closed — that needs a daemon endpoint.)
enum BackgroundRefresh {
    static let identifier = "io.zhoulab.hop.spike.refresh"

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
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, model: AppModel) {
        schedule()   // always queue the next one, successful or not
        let work = Task {
            await model.refreshSessions(silent: true)   // posts notifications itself
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
