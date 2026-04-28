import Foundation

protocol TripPromptNotificationService {
    func requestPermissionsIfNeeded()
    func notifyLeadTime(sessionID: UUID, etaMinutes: Int)
    func notifyDestinationReached(sessionID: UUID)
    func scheduleNextTripPrompt(planItemID: UUID, tripTitle: String, fireAt: Date)
    func cancelNextTripPrompt(planItemID: UUID)
}

