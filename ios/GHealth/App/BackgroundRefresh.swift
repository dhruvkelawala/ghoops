@preconcurrency import BackgroundTasks
import GHealthCore

@MainActor
enum BackgroundRefresh {
    #if DEBUG
    static var scheduling = "not scheduled"
    static var registered = false
    #endif
    static let identifier = "io.ghealth.app.refresh"
    static func register(model: AppModel) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let work = Task { @MainActor in
                let success = await model.backgroundRefresh()
                schedule()
                task.setTaskCompleted(success: success)
            }
            task.expirationHandler = {
                work.cancel()
                Task { await SnapshotRefresher.shared.cancel() }
            }
        }
        #if DEBUG
        self.registered = registered
        #endif
    }
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            scheduling = "submitted"
            #endif
        } catch {
            #if DEBUG
            scheduling = "scheduler error \((error as NSError).code)"
            #endif
        }
    }
}
