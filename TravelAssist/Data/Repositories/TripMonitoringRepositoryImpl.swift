import Combine
import CoreLocation
import Foundation
import ActivityKit

final class TripMonitoringRepositoryImpl: TripMonitoringRepository {
    private let locationService: LocationService
    private let etaEstimator: ETAEstimator
    private let alertService: FakeCallAlertService
    private let backgroundTaskScheduler: BackgroundTaskScheduler
    private let widgetSyncService: WidgetSyncService
    private let stationaryFreezeDistanceMeters: CLLocationDistance = 12
    private let maximumStationaryJitterMeters: CLLocationDistance = 35
    private let minimumArrivalClampMeters: CLLocationDistance = 20
    private let maximumArrivalClampMeters: CLLocationDistance = 45

    private var cancellables = Set<AnyCancellable>()
    private var intervalCancellable: AnyCancellable?
    private var estimateTask: Task<Void, Never>?
    private var hasTriggeredFakeCall = false
    private var hasReachedDestination = false
    private var liveActivity: Activity<TravelAssistWidgetAttributes>?

    private let sessionSubject = CurrentValueSubject<TripSession?, Never>(nil)
    private let snapshotSubject = CurrentValueSubject<TravelSnapshot?, Never>(nil)

    var sessionPublisher: AnyPublisher<TripSession?, Never> {
        sessionSubject.eraseToAnyPublisher()
    }

    var snapshotPublisher: AnyPublisher<TravelSnapshot?, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    init(
        locationService: LocationService,
        etaEstimator: ETAEstimator,
        alertService: FakeCallAlertService,
        backgroundTaskScheduler: BackgroundTaskScheduler,
        widgetSyncService: WidgetSyncService
    ) {
        self.locationService = locationService
        self.etaEstimator = etaEstimator
        self.alertService = alertService
        self.backgroundTaskScheduler = backgroundTaskScheduler
        self.widgetSyncService = widgetSyncService
        bindLocationUpdates()
    }

    func start(session: TripSession) {
        hasTriggeredFakeCall = false
        hasReachedDestination = false
        sessionSubject.send(session)

        alertService.requestPermissionsIfNeeded()
        locationService.requestPermissionsIfNeeded()
        locationService.startStandardUpdates()
        locationService.startSignificantUpdates()
        locationService.startMonitoringDestination(
            coordinate: session.destinationCoordinate,
            radius: destinationRegionRadius(for: session.leadTimeMinutes)
        )
        startLiveActivity(for: session)
        startIntervalChecks()
        backgroundTaskScheduler.scheduleRefresh()
    }

    func stop() {
        sessionSubject.send(nil)
        snapshotSubject.send(nil)
        hasTriggeredFakeCall = false
        hasReachedDestination = false

        estimateTask?.cancel()
        estimateTask = nil
        intervalCancellable?.cancel()
        alertService.cancelPendingFakeCall()
        locationService.stopUpdates()
        widgetSyncService.clear()
        Task { [weak self] in
            await self?.endLiveActivity()
        }
    }

    private func bindLocationUpdates() {
        locationService.locationPublisher
            .sink { [weak self] location in
                self?.scheduleEstimate(for: location)
            }
            .store(in: &cancellables)
    }

    private func startIntervalChecks() {
        intervalCancellable?.cancel()
        intervalCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let location = self.locationService.currentLocation else { return }
                self.scheduleEstimate(for: location)
            }
    }

    private func scheduleEstimate(for location: CLLocation) {
        estimateTask?.cancel()
        estimateTask = Task { [weak self] in
            await self?.process(location: location)
        }
    }

    private func destinationRegionRadius(for leadTimeMinutes: Int) -> CLLocationDistance {
        let speedMetersPerSecond = 9.72 // ~35 km/h fallback average
        let estimatedMeters = Double(leadTimeMinutes) * 60 * speedMetersPerSecond
        return min(max(estimatedMeters, 600), 4000)
    }

    private func process(location: CLLocation) async {
        guard let session = sessionSubject.value else { return }
        let sessionID = session.id

        let rawEstimate = await etaEstimator.estimateETA(from: location, to: session.destinationCoordinate)
        guard !Task.isCancelled else { return }
        guard let activeSession = sessionSubject.value, activeSession.id == sessionID else { return }

        let destinationLocation = CLLocation(
            latitude: session.destinationCoordinate.latitude,
            longitude: session.destinationCoordinate.longitude
        )
        let directDistanceMeters = max(0, location.distance(from: destinationLocation))
        let arrivalThresholdMeters = arrivalThreshold(for: location)

        let estimate: ETAEstimate
        if hasReachedDestination || directDistanceMeters <= arrivalThresholdMeters {
            hasReachedDestination = true
            estimate = ETAEstimate(distanceMeters: 0, etaSeconds: 0)
        } else {
            estimate = stabilizeEstimateIfStationary(rawEstimate, at: location)
        }

        let snapshot = TravelSnapshot(
            currentCoordinate: location.coordinate,
            distanceMeters: estimate.distanceMeters,
            etaSeconds: estimate.etaSeconds,
            updatedAt: .now
        )

        snapshotSubject.send(snapshot)
        widgetSyncService.sync(snapshot: snapshot, session: session)
        await updateLiveActivity(for: session, snapshot: snapshot)

        let leadTimeSeconds = TimeInterval(session.leadTimeMinutes * 60)
        if !hasTriggeredFakeCall && estimate.etaSeconds <= leadTimeSeconds {
            hasTriggeredFakeCall = true
            alertService.scheduleFakeCall(
                in: 1,
                message: "Your destination is close. ETA is about \(snapshot.etaMinutes) minute(s)."
            )
        } else if !hasTriggeredFakeCall && estimate.distanceMeters <= AppConstants.arrivalDistanceThresholdMeters {
            hasTriggeredFakeCall = true
            alertService.scheduleFakeCall(
                in: 1,
                message: "You are very close to your destination."
            )
        }
    }

    private func arrivalThreshold(for location: CLLocation) -> CLLocationDistance {
        let accuracy = max(0, location.horizontalAccuracy)
        return min(max(accuracy, minimumArrivalClampMeters), maximumArrivalClampMeters)
    }

    private func stabilizeEstimateIfStationary(_ estimate: ETAEstimate, at location: CLLocation) -> ETAEstimate {
        guard let previous = snapshotSubject.value else {
            return estimate
        }

        let previousLocation = CLLocation(
            latitude: previous.currentCoordinate.latitude,
            longitude: previous.currentCoordinate.longitude
        )
        let movedMeters = location.distance(from: previousLocation)
        let speed = max(location.speed, 0)
        let dynamicFreezeDistance = max(
            stationaryFreezeDistanceMeters,
            min(maximumStationaryJitterMeters, location.horizontalAccuracy * 0.6)
        )

        if movedMeters < dynamicFreezeDistance && speed < 0.8 {
            return ETAEstimate(
                distanceMeters: previous.distanceMeters,
                etaSeconds: previous.etaSeconds
            )
        }

        return ETAEstimate(
            distanceMeters: max(0, estimate.distanceMeters),
            etaSeconds: max(0, estimate.etaSeconds)
        )
    }

    private func startLiveActivity(for session: TripSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if liveActivity != nil { return }

        let attributes = TravelAssistWidgetAttributes(name: "TravelAssist")
        let initialState = TravelAssistWidgetAttributes.ContentState(
            etaMinutes: max(session.leadTimeMinutes, 1),
            statusText: "Trip started",
            progress: 0,
            distanceText: "--"
        )

        do {
            let content = ActivityContent(
                state: initialState,
                staleDate: Date().addingTimeInterval(120)
            )
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            liveActivity = nil
        }
    }

    private func updateLiveActivity(for session: TripSession, snapshot: TravelSnapshot) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if liveActivity == nil {
            startLiveActivity(for: session)
        }
        guard let liveActivity else { return }

        let progress = liveActivityProgress(for: session, snapshot: snapshot)
        let statusText = liveActivityStatusText(for: session, snapshot: snapshot)
        let state = TravelAssistWidgetAttributes.ContentState(
            etaMinutes: max(snapshot.etaMinutes, 0),
            statusText: statusText,
            progress: progress,
            distanceText: liveActivityDistanceText(snapshot.distanceMeters)
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(120)
        )
        await liveActivity.update(content)
    }

    private func endLiveActivity() async {
        guard let liveActivity else { return }
        await liveActivity.end(dismissalPolicy: .immediate)
        self.liveActivity = nil
    }

    private func liveActivityProgress(for session: TripSession, snapshot: TravelSnapshot) -> Double {
        let start = CLLocation(
            latitude: session.startCoordinate.latitude,
            longitude: session.startCoordinate.longitude
        )
        let destination = CLLocation(
            latitude: session.destinationCoordinate.latitude,
            longitude: session.destinationCoordinate.longitude
        )
        let totalDistance = max(start.distance(from: destination), 1)
        let progress = 1 - (snapshot.distanceMeters / totalDistance)
        return min(max(progress, 0), 1)
    }

    private func liveActivityStatusText(for session: TripSession, snapshot: TravelSnapshot) -> String {
        if snapshot.distanceMeters <= AppConstants.arrivalDistanceThresholdMeters {
            return "Reached destination"
        }
        if snapshot.etaMinutes <= session.leadTimeMinutes {
            return "Almost there"
        }
        return "On the way"
    }

    private func liveActivityDistanceText(_ distanceMeters: CLLocationDistance) -> String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m remaining"
        }
        return String(format: "%.1f km remaining", distanceMeters / 1000)
    }
}

struct TravelAssistWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var etaMinutes: Int
        var statusText: String
        var progress: Double
        var distanceText: String
    }

    var name: String
}
