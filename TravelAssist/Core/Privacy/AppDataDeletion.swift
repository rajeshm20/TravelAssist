import Foundation
import Security
import UserNotifications

extension Notification.Name {
    static let appDataDeleted = Notification.Name("travelassist.appDataDeleted")
}

enum AppDataDeletion {
    static func deleteAllData() {
        deleteLocalGPXFiles()
        deleteGPXEncryptionKey()
        clearUserDefaults()
        clearNotifications()
        NotificationCenter.default.post(name: .appDataDeleted, object: nil)
    }

    private static func deleteLocalGPXFiles() {
        let store = GPXLocalFileStore()
        guard let directory = try? store.localHistoryDirectory() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func deleteGPXEncryptionKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "travelassist.gpx.encryption",
            kSecAttrAccount as String: "symmetric-key",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()

        if let appGroup = UserDefaults(suiteName: AppConstants.appGroupID) {
            appGroup.removePersistentDomain(forName: AppConstants.appGroupID)
            appGroup.synchronize()
        }
    }

    private static func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}

