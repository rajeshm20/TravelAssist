import Foundation

protocol StartTripMonitoringUseCase {
    func execute(session: TripSession)
}

struct StartTripMonitoringUseCaseImpl: StartTripMonitoringUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute(session: TripSession) {
        repository.start(session: session)
    }
}

