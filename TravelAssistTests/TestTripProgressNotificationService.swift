import Foundation
@testable import TravelAssist

struct TestTripProgressNotificationService: TripProgressNotificationService {
    func requestPermissionsIfNeeded() {}
    func scheduleQuarterProgressNotifications(sessionID: UUID, tripTitle: String?, startedAt: Date, estimatedDurationSeconds: TimeInterval) {}
    func cancelQuarterProgressNotifications(sessionID: UUID) {}
}

