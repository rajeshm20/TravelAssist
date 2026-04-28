import Foundation
import UserNotifications

final class LocalTripPromptNotificationService: TripPromptNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestPermissionsIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func notifyLeadTime(sessionID: UUID, etaMinutes: Int) {
        requestPermissionsIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "Travel Assist"
        content.body = "Your destination is close. ETA is about \(max(etaMinutes, 0)) minute(s)."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: leadID(sessionID), content: content, trigger: trigger))
    }

    func notifyDestinationReached(sessionID: UUID) {
        requestPermissionsIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "Travel Assist"
        content.body = "You’ve reached your destination."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: reachedID(sessionID), content: content, trigger: trigger))
    }

    func scheduleNextTripPrompt(planItemID: UUID, tripTitle: String, fireAt: Date) {
        requestPermissionsIfNeeded()
        cancelNextTripPrompt(planItemID: planItemID)

        let content = UNMutableNotificationContent()
        content.title = "Next trip"
        content.body = "Start trip to \(tripTitle) now?"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = AppConstants.nextTripPromptCategoryID

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        center.add(UNNotificationRequest(identifier: nextTripID(planItemID), content: content, trigger: trigger))
    }

    func cancelNextTripPrompt(planItemID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [nextTripID(planItemID)])
        center.removeDeliveredNotifications(withIdentifiers: [nextTripID(planItemID)])
    }

    private func leadID(_ sessionID: UUID) -> String { "travelassist.alert.leadtime.\(sessionID.uuidString)" }
    private func reachedID(_ sessionID: UUID) -> String { "travelassist.alert.reached.\(sessionID.uuidString)" }
    private func nextTripID(_ planItemID: UUID) -> String { "travelassist.alert.nexttrip.\(planItemID.uuidString)" }
}

