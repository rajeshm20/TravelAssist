import Combine
import Foundation

struct TripHistorySession: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let startLatitude: Double
    let startLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let pointsCount: Int
    let gpxFileName: String
    let gpxFilePath: String
    let completionStatus: JourneyCompletionStatus
    let selectedJourneyMode: JourneyMode
    let finalDetectedActivity: DetectedJourneyActivity

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

protocol TripMonitoringRepository {
    var sessionPublisher: AnyPublisher<TripSession?, Never> { get }
    var snapshotPublisher: AnyPublisher<TravelSnapshot?, Never> { get }
    var historyPublisher: AnyPublisher<[TripHistorySession], Never> { get }

    func start(session: TripSession)
    func stop()
    func refreshFromBackground()
}
