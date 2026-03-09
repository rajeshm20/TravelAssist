import BackgroundTasks
import Foundation

protocol BackgroundTaskScheduler {
    func register()
    func scheduleRefresh()
}

final class IOSBackgroundTaskScheduler: BackgroundTaskScheduler {
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConstants.backgroundRefreshTaskID,
            using: nil
        ) { [weak self] task in
            self?.handleAppRefresh(task: task as? BGAppRefreshTask)
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort scheduling; ignored if system declines.
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask?) {
        guard let task else { return }

        scheduleRefresh()
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        task.setTaskCompleted(success: true)
    }
}

