import Foundation
import AudioToolbox
import UserNotifications

final class LocalFakeCallAlertService: FakeCallAlertService {
    private let center = UNUserNotificationCenter.current()

    func requestPermissionsIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleFakeCall(in seconds: TimeInterval, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Incoming Call"
        content.subtitle = "TravelAssist Alert"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "FAKE_CALL_ALERT"
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: AppConstants.fakeCallNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)

        // If app is currently active, trigger haptic at scheduled time as a fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, seconds)) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func cancelPendingFakeCall() {
        center.removePendingNotificationRequests(withIdentifiers: [AppConstants.fakeCallNotificationID])
    }
}
