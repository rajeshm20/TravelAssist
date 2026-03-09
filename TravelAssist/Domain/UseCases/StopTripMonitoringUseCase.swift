import Foundation

protocol StopTripMonitoringUseCase {
    func execute()
}

struct StopTripMonitoringUseCaseImpl: StopTripMonitoringUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute() {
        repository.stop()
    }
}

