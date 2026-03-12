import Foundation

@MainActor
final class AppContainer {
    private let backgroundTaskScheduler: BackgroundTaskScheduler
    private let tripMonitoringRepository: TripMonitoringRepository

    private let buildTripSessionUseCase: BuildTripSessionUseCase
    private let prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase
    private let startUseCase: StartTripMonitoringUseCase
    private let updateJourneyModeUseCase: UpdateJourneyModeUseCase
    private let recordTripUserActionUseCase: RecordTripUserActionUseCase
    private let stopUseCase: StopTripMonitoringUseCase
    private let triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    private let observeUseCase: ObserveTripStateUseCase

    init() {
        let locationService = CoreLocationService()
        let etaEstimator = MapKitETAEstimator()
        let alertService = LocalFakeCallAlertService()
        let bgScheduler = IOSBackgroundTaskScheduler()
        let widgetSync = SharedDefaultsWidgetSyncService(appGroupID: AppConstants.appGroupID)
        let currentLocationProvider = CurrentLocationProviderAdapter(locationService: locationService)

        let repository = TripMonitoringRepositoryImpl(
            locationService: locationService,
            etaEstimator: etaEstimator,
            alertService: alertService,
            backgroundTaskScheduler: bgScheduler,
            widgetSyncService: widgetSync
        )

        self.backgroundTaskScheduler = bgScheduler
        self.tripMonitoringRepository = repository
        self.buildTripSessionUseCase = BuildTripSessionUseCaseImpl(locationProvider: currentLocationProvider)
        self.prepareCurrentLocationUseCase = PrepareCurrentLocationUseCaseImpl(locationProvider: currentLocationProvider)
        self.startUseCase = StartTripMonitoringUseCaseImpl(repository: repository)
        self.updateJourneyModeUseCase = UpdateJourneyModeUseCaseImpl(repository: repository)
        self.recordTripUserActionUseCase = RecordTripUserActionUseCaseImpl(repository: repository)
        self.stopUseCase = StopTripMonitoringUseCaseImpl(repository: repository)
        self.triggerTestFakeCallUseCase = TriggerTestFakeCallUseCaseImpl(repository: repository)
        self.observeUseCase = ObserveTripStateUseCaseImpl(repository: repository)

        // Register once during container creation so scheduler is ready before any restore flow schedules refresh.
        self.backgroundTaskScheduler.register { [weak self] in
            self?.tripMonitoringRepository.refreshFromBackground()
        }
    }

    func registerBackgroundTasks() {
        backgroundTaskScheduler.register { [weak self] in
            self?.tripMonitoringRepository.refreshFromBackground()
        }
    }

    func makeTripSetupViewModel() -> TripSetupViewModel {
        TripSetupViewModel(
            buildTripSessionUseCase: buildTripSessionUseCase,
            prepareCurrentLocationUseCase: prepareCurrentLocationUseCase,
            startUseCase: startUseCase,
            updateJourneyModeUseCase: updateJourneyModeUseCase,
            recordTripUserActionUseCase: recordTripUserActionUseCase,
            triggerTestFakeCallUseCase: triggerTestFakeCallUseCase
        )
    }

    func makeMonitoringViewModel() -> MonitoringViewModel {
        MonitoringViewModel(
            observeUseCase: observeUseCase,
            stopUseCase: stopUseCase
        )
    }
}
