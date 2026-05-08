import CoreLocation
import Foundation

@MainActor
final class AppContainer {
    private let locationService: LocationService
    private let backgroundTaskScheduler: BackgroundTaskScheduler
    private let tripMonitoringRepository: TripMonitoringRepository
    private let iCloudHistorySyncController: ICloudHistorySyncController
    private let iCloudGPXSyncController: ICloudGPXSyncController
    private let iCloudJourneyPlanSyncController: ICloudJourneyPlanSyncController

    private let buildTripSessionUseCase: BuildTripSessionUseCase
    private let prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase
    private let startUseCase: StartTripMonitoringUseCase
    private let updateJourneyModeUseCase: UpdateJourneyModeUseCase
    private let addJourneyPlanItemUseCase: AddJourneyPlanItemUseCase
    private let replaceJourneyPlanItemsUseCase: ReplaceJourneyPlanItemsUseCase
    private let recordTripUserActionUseCase: RecordTripUserActionUseCase
    private let stopUseCase: StopTripMonitoringUseCase
    private let triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    private let startPendingNextTripUseCase: StartPendingNextTripUseCase
    private let clearPendingNextTripUseCase: ClearPendingNextTripUseCase
    private let observeUseCase: ObserveTripStateUseCase

    init() {
        let locationService: LocationService
        #if DEBUG
        if Self.shouldUseSimulatedLocation {
            locationService = SimulatedLocationService(
                initialCoordinate: Self.simulatedStartCoordinate ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                speedMetersPerSecond: Self.simulatedSpeedMetersPerSecond ?? 15,
                updateIntervalSeconds: Self.simulatedUpdateIntervalSeconds ?? 1
            )
        } else {
            locationService = CoreLocationService()
        }
        #else
        locationService = CoreLocationService()
        #endif

        self.locationService = locationService
        let etaEstimator = MapKitETAEstimator()
        let promptService = LocalTripPromptNotificationService()
        let progressNotificationService = LocalTripProgressNotificationService()
        let bgScheduler = IOSBackgroundTaskScheduler()
        let widgetSync = SharedDefaultsWidgetSyncService(appGroupID: AppConstants.appGroupID)
        let currentLocationProvider = CurrentLocationProviderAdapter(locationService: locationService)

        let repository = TripMonitoringRepositoryImpl(
            locationService: locationService,
            etaEstimator: etaEstimator,
            promptService: promptService,
            progressNotificationService: progressNotificationService,
            backgroundTaskScheduler: bgScheduler,
            widgetSyncService: widgetSync
        )

        self.backgroundTaskScheduler = bgScheduler
        self.tripMonitoringRepository = repository
        self.iCloudHistorySyncController = ICloudHistorySyncController(repository: repository)
        self.iCloudGPXSyncController = ICloudGPXSyncController(repository: repository)
        self.iCloudJourneyPlanSyncController = ICloudJourneyPlanSyncController(repository: repository)
        self.buildTripSessionUseCase = BuildTripSessionUseCaseImpl(locationProvider: currentLocationProvider)
        self.prepareCurrentLocationUseCase = PrepareCurrentLocationUseCaseImpl(locationProvider: currentLocationProvider)
        self.startUseCase = StartTripMonitoringUseCaseImpl(repository: repository)
        self.updateJourneyModeUseCase = UpdateJourneyModeUseCaseImpl(repository: repository)
        self.addJourneyPlanItemUseCase = AddJourneyPlanItemUseCaseImpl(repository: repository)
        self.replaceJourneyPlanItemsUseCase = ReplaceJourneyPlanItemsUseCaseImpl(repository: repository)
        self.recordTripUserActionUseCase = RecordTripUserActionUseCaseImpl(repository: repository)
        self.stopUseCase = StopTripMonitoringUseCaseImpl(repository: repository)
        self.triggerTestFakeCallUseCase = TriggerTestFakeCallUseCaseImpl(repository: repository)
        self.startPendingNextTripUseCase = StartPendingNextTripUseCaseImpl(repository: repository)
        self.clearPendingNextTripUseCase = ClearPendingNextTripUseCaseImpl(repository: repository)
        self.observeUseCase = ObserveTripStateUseCaseImpl(repository: repository)

        // Register once during container creation so scheduler is ready before any restore flow schedules refresh.
        self.backgroundTaskScheduler.register { [weak self] in
            self?.tripMonitoringRepository.refreshFromBackground()
        }
    }

    #if DEBUG
    private static let simulateLocationFlag = "-travelassist_simulate_location"
    private static let simulateStartLatFlag = "-travelassist_simulate_start_lat"
    private static let simulateStartLonFlag = "-travelassist_simulate_start_lon"
    private static let simulateSpeedFlag = "-travelassist_simulate_speed_mps"
    private static let simulateIntervalFlag = "-travelassist_simulate_interval_s"

    private static var shouldUseSimulatedLocation: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: simulateLocationFlag) else { return false }
        let next = args.index(after: idx)
        if next < args.endIndex {
            return args[next] != "0"
        }
        return true
    }

    private static var simulatedStartCoordinate: CLLocationCoordinate2D? {
        guard let lat = launchArgumentDouble(simulateStartLatFlag),
              let lon = launchArgumentDouble(simulateStartLonFlag) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static var simulatedSpeedMetersPerSecond: Double? {
        launchArgumentDouble(simulateSpeedFlag)
    }

    private static var simulatedUpdateIntervalSeconds: Double? {
        launchArgumentDouble(simulateIntervalFlag)
    }

    private static func launchArgumentDouble(_ flag: String) -> Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        guard next < args.endIndex else { return nil }
        return Double(args[next])
    }
    #endif

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
            addJourneyPlanItemUseCase: addJourneyPlanItemUseCase,
            replaceJourneyPlanItemsUseCase: replaceJourneyPlanItemsUseCase,
            recordTripUserActionUseCase: recordTripUserActionUseCase,
            triggerTestFakeCallUseCase: triggerTestFakeCallUseCase,
            startPendingNextTripUseCase: startPendingNextTripUseCase,
            clearPendingNextTripUseCase: clearPendingNextTripUseCase
        )
    }

    func makeMonitoringViewModel() -> MonitoringViewModel {
        MonitoringViewModel(
            observeUseCase: observeUseCase,
            stopUseCase: stopUseCase
        )
    }

    func makeSplashViewModel() -> TravelSplashViewModel {
        TravelSplashViewModel(locationService: locationService)
    }
}
