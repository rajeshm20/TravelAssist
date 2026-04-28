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

protocol StartPendingNextTripUseCase {
    func execute()
}

struct StartPendingNextTripUseCaseImpl: StartPendingNextTripUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute() {
        repository.startPendingNextTripIfAvailable()
    }
}

protocol ClearPendingNextTripUseCase {
    func execute()
}

struct ClearPendingNextTripUseCaseImpl: ClearPendingNextTripUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute() {
        repository.clearPendingNextTrip()
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

protocol AddJourneyPlanItemUseCase {
    func execute(item: JourneyPlanItem)
}

struct AddJourneyPlanItemUseCaseImpl: AddJourneyPlanItemUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute(item: JourneyPlanItem) {
        repository.addJourneyPlanItem(item)
    }
}

protocol ReplaceJourneyPlanItemsUseCase {
    func execute(items: [JourneyPlanItem])
}

struct ReplaceJourneyPlanItemsUseCaseImpl: ReplaceJourneyPlanItemsUseCase {
    private let repository: TripMonitoringRepository

    init(repository: TripMonitoringRepository) {
        self.repository = repository
    }

    func execute(items: [JourneyPlanItem]) {
        repository.replaceJourneyPlanItems(items)
    }
}
