import Foundation

@MainActor
final class AppContainer {
    private let backgroundTaskScheduler: BackgroundTaskScheduler

    private let buildTripSessionUseCase: BuildTripSessionUseCase
    private let prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase
    private let startUseCase: StartTripMonitoringUseCase
    private let stopUseCase: StopTripMonitoringUseCase
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
        self.buildTripSessionUseCase = BuildTripSessionUseCaseImpl(locationProvider: currentLocationProvider)
        self.prepareCurrentLocationUseCase = PrepareCurrentLocationUseCaseImpl(locationProvider: currentLocationProvider)
        self.startUseCase = StartTripMonitoringUseCaseImpl(repository: repository)
        self.stopUseCase = StopTripMonitoringUseCaseImpl(repository: repository)
        self.observeUseCase = ObserveTripStateUseCaseImpl(repository: repository)
    }

    func registerBackgroundTasks() {
        backgroundTaskScheduler.register()
    }

    func makeTripSetupViewModel() -> TripSetupViewModel {
        TripSetupViewModel(
            buildTripSessionUseCase: buildTripSessionUseCase,
            prepareCurrentLocationUseCase: prepareCurrentLocationUseCase,
            startUseCase: startUseCase
        )
    }

    func makeMonitoringViewModel() -> MonitoringViewModel {
        MonitoringViewModel(
            observeUseCase: observeUseCase,
            stopUseCase: stopUseCase
        )
    }
}
