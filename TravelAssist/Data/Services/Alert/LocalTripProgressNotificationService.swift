import Foundation
import UserNotifications

final class LocalTripProgressNotificationService: TripProgressNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestPermissionsIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func scheduleQuarterProgressNotifications(
        sessionID: UUID,
        tripTitle: String?,
        startedAt: Date,
        estimatedDurationSeconds: TimeInterval
    ) {
        cancelQuarterProgressNotifications(sessionID: sessionID)

        let duration = max(estimatedDurationSeconds, 0)
        guard duration > 0 else { return }

        let quarterSeconds = duration / 4
        let now = Date()
        let title = tripTitle?.isEmpty == false ? (tripTitle ?? "Trip") : "Trip"

        for quarter in 1...4 {
            let progressPercent = quarter * 25
            let fireDate = startedAt.addingTimeInterval(quarterSeconds * Double(quarter))
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Trip update: \(progressPercent)% of estimated time elapsed."
            content.sound = .default

            let triggerComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(sessionID: sessionID, quarter: quarter),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func cancelQuarterProgressNotifications(sessionID: UUID) {
        let ids = (1...4).map { identifier(sessionID: sessionID, quarter: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func identifier(sessionID: UUID, quarter: Int) -> String {
        "\(AppConstants.tripProgressNotificationPrefix).\(sessionID.uuidString).q\(quarter)"
    }
}

