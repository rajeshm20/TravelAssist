import Foundation
import UIKit
import UserNotifications
import AudioToolbox

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        return true
    }

    private func registerNotificationCategories() {
        let start = UNNotificationAction(
            identifier: AppConstants.fakeCallDecisionActionStartID,
            title: "Start Next Trip",
            options: [.foreground]
        )
        let skip = UNNotificationAction(
            identifier: AppConstants.fakeCallDecisionActionSkipID,
            title: "Skip",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: AppConstants.fakeCallDecisionCategoryID,
            actions: [start, skip],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == AppConstants.fakeCallNotificationID {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == AppConstants.fakeCallNotificationID {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        if response.notification.request.identifier == AppConstants.fakeCallDecisionNotificationID {
            FakeCallDecisionCenter.shared.handleNotificationAction(response.actionIdentifier)
        }
        completionHandler()
    }
}
