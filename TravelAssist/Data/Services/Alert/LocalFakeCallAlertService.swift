import Foundation
import UserNotifications

final class LocalFakeCallAlertService: NSObject, FakeCallAlertService {
    private let center = UNUserNotificationCenter.current()
    private var pendingPromptMessage = AppConstants.fakeCallNotificationMessage
    private var scheduledCallWorkItem: DispatchWorkItem?
    override init() {}

    func requestPermissionsIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleFakeCall(in seconds: TimeInterval, message: String) {
        pendingPromptMessage = normalizedPrompt(from: message)
        scheduledCallWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduleAlertNotification()
        }
        scheduledCallWorkItem = workItem

        if seconds <= 0 {
            if Thread.isMainThread {
                workItem.perform()
            } else {
                DispatchQueue.main.sync {
                    workItem.perform()
                }
            }
            if scheduledCallWorkItem === workItem {
                scheduledCallWorkItem = nil
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    func cancelPendingFakeCall() {
        center.removePendingNotificationRequests(withIdentifiers: [AppConstants.fakeCallNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [AppConstants.fakeCallNotificationID])
        scheduledCallWorkItem?.cancel()
        scheduledCallWorkItem = nil
    }

    private func normalizedPrompt(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AppConstants.fakeCallNotificationMessage
        }
        return trimmed
    }

    private func scheduleAlertNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Travel Assist"
        content.body = pendingPromptMessage
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: AppConstants.fakeCallNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
