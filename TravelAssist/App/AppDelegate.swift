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

        let start = UNNotificationAction(
            identifier: AppConstants.nextTripStartActionID,
            title: "Start",
            options: []
        )
        let notNow = UNNotificationAction(
            identifier: AppConstants.nextTripNotNowActionID,
            title: "Not now",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: AppConstants.nextTripPromptCategoryID,
            actions: [start, notNow],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        if id == AppConstants.fakeCallNotificationID || id.hasPrefix("travelassist.alert.") {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case AppConstants.nextTripStartActionID:
            NextTripPromptCenter.postStartNextTripRequested()
        case AppConstants.nextTripNotNowActionID:
            NextTripPromptCenter.postClearPendingNextTripRequested()
        default:
            break
        }
        let id = response.notification.request.identifier
        if id == AppConstants.fakeCallNotificationID || id.hasPrefix("travelassist.alert.") {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        completionHandler()
    }
}
