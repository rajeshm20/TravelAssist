import Foundation

extension Notification.Name {
    static let startNextTripRequested = Notification.Name("travelassist.startNextTripRequested")
    static let clearPendingNextTripRequested = Notification.Name("travelassist.clearPendingNextTripRequested")
    static let nextTripPromptScheduled = Notification.Name("travelassist.nextTripPromptScheduled")
    static let tripVoicePromptRequested = Notification.Name("travelassist.tripVoicePromptRequested")
}

struct NextTripPromptScheduledPayload {
    let planItemID: UUID
    let tripTitle: String
    let fireAt: Date

    fileprivate static let planItemIDKey = "planItemID"
    fileprivate static let tripTitleKey = "tripTitle"
    fileprivate static let fireAtKey = "fireAt"

    static func from(userInfo: [AnyHashable: Any]?) -> NextTripPromptScheduledPayload? {
        guard let planItemID = userInfo?[planItemIDKey] as? UUID,
              let tripTitle = userInfo?[tripTitleKey] as? String,
              let fireAt = userInfo?[fireAtKey] as? Date else {
            return nil
        }
        return NextTripPromptScheduledPayload(planItemID: planItemID, tripTitle: tripTitle, fireAt: fireAt)
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.planItemIDKey: planItemID,
            Self.tripTitleKey: tripTitle,
            Self.fireAtKey: fireAt
        ]
    }
}

struct TripVoicePromptPayload {
    let message: String

    fileprivate static let messageKey = "message"

    static func from(userInfo: [AnyHashable: Any]?) -> TripVoicePromptPayload? {
        guard let message = userInfo?[messageKey] as? String else { return nil }
        return TripVoicePromptPayload(message: message)
    }

    var userInfo: [AnyHashable: Any] {
        [Self.messageKey: message]
    }
}

enum NextTripPromptCenter {
    static func postStartNextTripRequested() {
        NotificationCenter.default.post(name: .startNextTripRequested, object: nil)
    }

    static func postClearPendingNextTripRequested() {
        NotificationCenter.default.post(name: .clearPendingNextTripRequested, object: nil)
    }

    static func postNextTripPromptScheduled(planItemID: UUID, tripTitle: String, fireAt: Date) {
        let payload = NextTripPromptScheduledPayload(planItemID: planItemID, tripTitle: tripTitle, fireAt: fireAt)
        NotificationCenter.default.post(name: .nextTripPromptScheduled, object: nil, userInfo: payload.userInfo)
    }

    static func postTripVoicePromptRequested(message: String) {
        let payload = TripVoicePromptPayload(message: message)
        NotificationCenter.default.post(name: .tripVoicePromptRequested, object: nil, userInfo: payload.userInfo)
    }
}
