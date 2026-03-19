import BackgroundTasks
import Foundation

protocol BackgroundTaskScheduler {
    func register(refreshHandler: @escaping () -> Void)
    func scheduleRefresh()
}

final class IOSBackgroundTaskScheduler: BackgroundTaskScheduler {
    private let refreshIntervalSeconds: TimeInterval = 30 * 60
    private var refreshHandler: (() -> Void)?
    private var isRegistered = false

    func register(refreshHandler: @escaping () -> Void) {
        self.refreshHandler = refreshHandler
        guard !isRegistered else { return }

        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConstants.backgroundRefreshTaskID,
            using: nil
        ) { [weak self] task in
            self?.handleAppRefresh(task: task as? BGAppRefreshTask)
        }
    }

    func scheduleRefresh() {
        guard isRegistered else { return }

        let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshIntervalSeconds)

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.backgroundRefreshTaskID)
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort scheduling; ignored if system declines.
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask?) {
        guard let task else { return }

        scheduleRefresh()
        refreshHandler?()
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        task.setTaskCompleted(success: true)
    }
}
