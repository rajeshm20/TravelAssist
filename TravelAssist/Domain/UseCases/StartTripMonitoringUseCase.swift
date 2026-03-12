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

protocol UpdateJourneyModeUseCase {
    func execute(mode: JourneyMode)
}

struct UpdateJourneyModeUseCaseImpl: UpdateJourneyModeUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute(mode: JourneyMode) {
        repository.updateJourneyMode(mode)
    }
}

protocol RecordTripUserActionUseCase {
    func execute(status: String)
}

struct RecordTripUserActionUseCaseImpl: RecordTripUserActionUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute(status: String) {
        repository.recordUserAction(status)
    }
}
