import Combine
import Foundation

protocol TripMonitoringRepository {
    var sessionPublisher: AnyPublisher<TripSession?, Never> { get }
    var snapshotPublisher: AnyPublisher<TravelSnapshot?, Never> { get }

    func start(session: TripSession)
    func stop()
}

