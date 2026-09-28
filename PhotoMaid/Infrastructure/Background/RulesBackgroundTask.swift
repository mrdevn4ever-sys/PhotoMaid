import BackgroundTasks
import Foundation

/// Best effort: iOS entscheidet, ob und wann die Aufgabe läuft. Keine garantierten
/// nächtlichen Vollscans. Die Kernprüfung erfolgt bei Start/Resume (inkrementell, abbrechbar).
enum RulesBackgroundTask {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "app.photomaid.ios") + ".rules.refresh" }

    static func register(run: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let box = UncheckedBox(task)
            let work = Task {
                await run()
                box.value.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
            schedule()
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
