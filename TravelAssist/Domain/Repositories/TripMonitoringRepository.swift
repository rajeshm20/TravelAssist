import Combine
import Foundation

struct TripActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let status: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        status: String,
        latitude: Double?,
        longitude: Double?,
        timestamp: Date
    ) {
        self.id = id
        self.status = status
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

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
    let activityEvents: [TripActivityEvent]

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

protocol TripMonitoringRepository {
    var sessionPublisher: AnyPublisher<TripSession?, Never> { get }
    var snapshotPublisher: AnyPublisher<TravelSnapshot?, Never> { get }
    var historyPublisher: AnyPublisher<[TripHistorySession], Never> { get }
    var journeyPlanPublisher: AnyPublisher<[JourneyPlanItem], Never> { get }

    func start(session: TripSession)
    func stop()
    func updateJourneyMode(_ mode: JourneyMode)
    func addJourneyPlanItem(_ item: JourneyPlanItem)
    func replaceJourneyPlanItems(_ items: [JourneyPlanItem])
    func recordUserAction(_ status: String)
    func triggerFakeCallForTesting()
    func refreshFromBackground()
}
