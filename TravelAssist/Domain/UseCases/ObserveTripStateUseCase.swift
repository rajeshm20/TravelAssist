import Combine
import Foundation

protocol ObserveTripStateUseCase {
    func sessionStream() -> AnyPublisher<TripSession?, Never>
    func snapshotStream() -> AnyPublisher<TravelSnapshot?, Never>
}

struct ObserveTripStateUseCaseImpl: ObserveTripStateUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func sessionStream() -> AnyPublisher<TripSession?, Never> {
        repository.sessionPublisher
    }

    func snapshotStream() -> AnyPublisher<TravelSnapshot?, Never> {
        repository.snapshotPublisher
    }
}

