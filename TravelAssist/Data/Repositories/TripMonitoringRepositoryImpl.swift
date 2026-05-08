import Combine
import CoreLocation
import Foundation
import ActivityKit
import UIKit

	final class TripMonitoringRepositoryImpl: TripMonitoringRepository {
	    private enum StorageKeys {
	        static let activeSession = "trip.active.session"
	        static let historySessions = "trip.history.sessions"
	        static let journeyPlanItems = "trip.journey.plan"
	        static let journeyPlanDeleted = "trip.journey.plan.deleted"
	        static let liveActivityID = "trip.live.activity.id"
	    }

    private let locationService: LocationService
    private let etaEstimator: ETAEstimator
    private let promptService: TripPromptNotificationService
    private let progressNotificationService: TripProgressNotificationService
    private let backgroundTaskScheduler: BackgroundTaskScheduler
    private let widgetSyncService: WidgetSyncService
    private let defaults: UserDefaults?
    private let gpxFileStore = GPXLocalFileStore()

    private let stationaryFreezeDistanceMeters: CLLocationDistance = 12
    private let maximumStationaryJitterMeters: CLLocationDistance = 35
    private let minimumArrivalClampMeters: CLLocationDistance = 20
    private let maximumArrivalClampMeters: CLLocationDistance = 45
    private let routePointMinimumDistanceMeters: CLLocationDistance = 12
    private let routePointMinimumIntervalSeconds: TimeInterval = 20
    private let intervalCheckSeconds: TimeInterval = 10 * 60
    private let idleTimeoutSeconds: TimeInterval = 10 * 60
    private let maxActivityEventsPerSession = 4000
    private let liveActivityMinimumUpdateIntervalSeconds: TimeInterval = 60
    private let liveActivityMinimumProgressDelta = 0.02
    private let journeyPlanMatchDistanceMeters: CLLocationDistance = 150

    private var cancellables = Set<AnyCancellable>()
    private var intervalCancellable: AnyCancellable?
    private var estimateTask: Task<Void, Never>?
    private var hasTriggeredFakeCall = false
    private var hasReachedDestination = false
    private var hasScheduledProgressNotifications = false
    private var progressNotificationSessionID: UUID?
    private var liveActivity: Activity<TravelAssistWidgetAttributes>?
    private var currentRoutePoints: [PersistedTrackPoint] = []
    private var currentActivityEvents: [TripActivityEvent] = []

    private var runState: MonitoringRunState = .active
    private var lastMovementDetectedAt: Date?
    private var lastMovementLocation: CLLocation?
    private var latestDetectedActivity: DetectedJourneyActivity = .unknown
    private var lastLiveActivityState: TravelAssistWidgetAttributes.ContentState?
    private var lastLiveActivityUpdateAt: Date?
    private let activityDetector = JourneyActivityDetector()
    private var isInBackground = false

    private static let liveActivityStartQueue = DispatchQueue(label: "trip.monitoring.liveactivity.start")

	    private let sessionSubject = CurrentValueSubject<TripSession?, Never>(nil)
	    private let snapshotSubject = CurrentValueSubject<TravelSnapshot?, Never>(nil)
	    private let historySubject = CurrentValueSubject<[TripHistorySession], Never>([])
	    private let journeyPlanSubject = CurrentValueSubject<[JourneyPlanItem], Never>([])
	    private let journeyPlanDeletedSubject = CurrentValueSubject<[JourneyPlanTombstone], Never>([])

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var sessionPublisher: AnyPublisher<TripSession?, Never> {
        sessionSubject.eraseToAnyPublisher()
    }

    var snapshotPublisher: AnyPublisher<TravelSnapshot?, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    var historyPublisher: AnyPublisher<[TripHistorySession], Never> {
        historySubject.eraseToAnyPublisher()
    }

    var journeyPlanPublisher: AnyPublisher<[JourneyPlanItem], Never> {
        journeyPlanSubject.eraseToAnyPublisher()
    }

    init(
        locationService: LocationService,
        etaEstimator: ETAEstimator,
        promptService: TripPromptNotificationService,
        progressNotificationService: TripProgressNotificationService,
        backgroundTaskScheduler: BackgroundTaskScheduler,
        widgetSyncService: WidgetSyncService,
        defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)
    ) {
        self.locationService = locationService
        self.etaEstimator = etaEstimator
        self.promptService = promptService
        self.progressNotificationService = progressNotificationService
        self.backgroundTaskScheduler = backgroundTaskScheduler
        self.widgetSyncService = widgetSyncService
        self.defaults = defaults

	        bindLocationUpdates()
	        bindAuthorizationUpdates()
	        bindAppLifecycle()
	        loadPersistedHistory()
	        loadPersistedJourneyPlanDeletions()
	        loadPersistedJourneyPlan()
	        cleanupLiveActivitiesIfNoPersistedSession()
	        restoreActiveSessionIfNeeded()

        NotificationCenter.default.publisher(for: .appDataDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExternalDataDeletion()
            }
            .store(in: &cancellables)
	    }

	    struct JourneyPlanTombstone: Codable, Equatable {
	        let id: UUID
	        let deletedAt: Date
	    }

    func start(session: TripSession) {
        if sessionSubject.value != nil {
            let previousStatus = resolvedManualStopStatus()
            completeAndStop(status: previousStatus, finalSnapshot: snapshotSubject.value)
        }

        let resolvedSession = resolvedSessionForStart(session)

        hasTriggeredFakeCall = false
        hasReachedDestination = false
        hasScheduledProgressNotifications = false
        progressNotificationSessionID = resolvedSession.id
        runState = .active
        lastMovementDetectedAt = Date()
        lastMovementLocation = locationService.currentLocation
        latestDetectedActivity = .unknown

        sessionSubject.send(resolvedSession)
        if let journeyPlanItemID = resolvedSession.journeyPlanItemID {
            markJourneyPlanItemInProgressAndRecomputeSchedule(id: journeyPlanItemID, startedAt: resolvedSession.startedAt)
        }

        progressNotificationService.requestPermissionsIfNeeded()
        if let journeyPlanItemID = resolvedSession.journeyPlanItemID,
           let planItem = journeyPlanSubject.value.first(where: { $0.id == journeyPlanItemID }) {
            hasScheduledProgressNotifications = true
            progressNotificationService.scheduleQuarterProgressNotifications(
                sessionID: resolvedSession.id,
                tripTitle: planItem.title,
                startedAt: resolvedSession.startedAt,
                estimatedDurationSeconds: planItem.estimatedTravelDurationSeconds
            )
        }
        snapshotSubject.send(nil)
        currentRoutePoints = [
            PersistedTrackPoint(
                latitude: resolvedSession.startCoordinate.latitude,
                longitude: resolvedSession.startCoordinate.longitude,
                timestamp: resolvedSession.startedAt
            )
        ]
        currentActivityEvents = []
        recordActivityEvent(
            status: "Monitoring started (\(resolvedSession.selectedJourneyMode.title))",
            latitude: locationService.currentLocation?.coordinate.latitude ?? resolvedSession.startCoordinate.latitude,
            longitude: locationService.currentLocation?.coordinate.longitude ?? resolvedSession.startCoordinate.longitude,
            timestamp: resolvedSession.startedAt
        )
        let destinationLabel = resolvedSession.journeyPlanItemID
            .flatMap { journeyPlanItemID in
                journeyPlanSubject.value.first(where: { $0.id == journeyPlanItemID })?.title
            }
            ?? String(
                format: "%.5f, %.5f",
                resolvedSession.destinationCoordinate.latitude,
                resolvedSession.destinationCoordinate.longitude
            )
        recordActivityEvent(
            status: "Destination set to \(destinationLabel)",
            latitude: resolvedSession.destinationCoordinate.latitude,
            longitude: resolvedSession.destinationCoordinate.longitude,
            timestamp: resolvedSession.startedAt
        )
        recordActivityEvent(
            status: "Lead time set to \(String(format: "%02d:%02d", resolvedSession.leadTimeMinutes / 60, resolvedSession.leadTimeMinutes % 60))",
            latitude: locationService.currentLocation?.coordinate.latitude ?? resolvedSession.startCoordinate.latitude,
            longitude: locationService.currentLocation?.coordinate.longitude ?? resolvedSession.startCoordinate.longitude,
            timestamp: resolvedSession.startedAt
        )
        recordActivityEvent(
            status: "Journey mode selected: \(resolvedSession.selectedJourneyMode.title)",
            latitude: locationService.currentLocation?.coordinate.latitude ?? resolvedSession.startCoordinate.latitude,
            longitude: locationService.currentLocation?.coordinate.longitude ?? resolvedSession.startCoordinate.longitude,
            timestamp: resolvedSession.startedAt
        )
        persistActiveSession(resolvedSession)

        locationService.requestPermissionsIfNeeded()
        locationService.startStandardUpdates()
        locationService.startSignificantUpdates()
        locationService.requestOneTimeLocation()
        locationService.startMonitoringDestination(
            coordinate: resolvedSession.destinationCoordinate,
            radius: destinationRegionRadius(for: resolvedSession.leadTimeMinutes)
        )
        widgetSyncService.sync(snapshot: nil, session: resolvedSession)
        widgetSyncService.syncJourneyPlan(journeyPlanSubject.value)
        startLiveActivity(for: resolvedSession)
        startIntervalChecks()
        backgroundTaskScheduler.scheduleRefresh()

        if let currentLocation = locationService.currentLocation {
            scheduleEstimate(for: currentLocation)
        }
    }

    func stop() {
        let status = resolvedManualStopStatus()
        completeAndStop(status: status, finalSnapshot: snapshotSubject.value)
    }

    func updateJourneyMode(_ mode: JourneyMode) {
        guard let activeSession = sessionSubject.value else { return }
        guard activeSession.selectedJourneyMode != mode else { return }

        let updatedSession = TripSession(
            id: activeSession.id,
            startCoordinate: activeSession.startCoordinate,
            destinationCoordinate: activeSession.destinationCoordinate,
            leadTimeMinutes: activeSession.leadTimeMinutes,
            selectedJourneyMode: mode,
            journeyPlanItemID: activeSession.journeyPlanItemID,
            startedAt: activeSession.startedAt
        )

        sessionSubject.send(updatedSession)

        if let snapshot = snapshotSubject.value {
            widgetSyncService.sync(snapshot: snapshot, session: updatedSession)
            Task { [weak self] in
                await self?.updateLiveActivity(for: updatedSession, snapshot: snapshot)
            }
        } else {
            widgetSyncService.sync(snapshot: nil, session: updatedSession)
        }

        let eventLocation = snapshotSubject.value?.currentCoordinate ?? locationService.currentLocation?.coordinate
        recordActivityEvent(
            status: "Journey mode changed to \(mode.title)",
            latitude: eventLocation?.latitude,
            longitude: eventLocation?.longitude,
            timestamp: Date()
        )

        persistActiveSession(updatedSession)

        if let currentLocation = locationService.currentLocation {
            scheduleEstimate(for: currentLocation, forceRouteEstimate: true)
        } else if let coordinate = snapshotSubject.value?.currentCoordinate {
            let fallbackLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            scheduleEstimate(for: fallbackLocation, forceRouteEstimate: true)
        }
    }

    func recordUserAction(_ status: String) {
        guard let activeSession = sessionSubject.value else { return }
        let coordinate = snapshotSubject.value?.currentCoordinate ?? locationService.currentLocation?.coordinate
        recordActivityEvent(
            status: status,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            timestamp: Date()
        )
        persistActiveSession(activeSession)
    }

	    func addJourneyPlanItem(_ item: JourneyPlanItem) {
	        clearDeletionIfRevived(itemID: item.id, itemUpdatedAt: item.updatedAt)
	        var updated = journeyPlanSubject.value
	        updated.removeAll { existing in
	            abs(existing.latitude - item.latitude) < 0.00001 &&
	            abs(existing.longitude - item.longitude) < 0.00001 &&
            abs(existing.plannedStartAt.timeIntervalSince(item.plannedStartAt)) < 60
        }
        updated.append(item)
        updated.sort { lhs, rhs in
            if lhs.plannedStartAt == rhs.plannedStartAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
        let dayStart = Calendar.current.startOfDay(for: item.userPlannedStartAt)
        updated = recomputeJourneyPlanSchedule(for: dayStart, items: updated)
        updated.sort { lhs, rhs in
            if lhs.plannedStartAt == rhs.plannedStartAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
        saveJourneyPlanItems(updated)
    }

	    func replaceJourneyPlanItems(_ items: [JourneyPlanItem]) {
	        recordDeletions(from: journeyPlanSubject.value, to: items, deletedAt: .now)
	        let sortedItems = items.sorted { lhs, rhs in
	            if lhs.plannedStartAt == rhs.plannedStartAt {
	                return lhs.createdAt < rhs.createdAt
	            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
        saveJourneyPlanItems(sortedItems)
    }

    func triggerFakeCallForTesting() {
        promptService.requestPermissionsIfNeeded()
        promptService.notifyDestinationReached(sessionID: UUID())
    }

    func startPendingNextTripIfAvailable() {
        guard sessionSubject.value == nil else { return }
        guard let seed = loadPendingNextTripSeed() else { return }
        guard let nextItem = journeyPlanSubject.value.first(where: { $0.id == seed.planItemID }) else {
            clearPendingNextTrip()
            return
        }

        let startCoordinate = locationService.currentLocation?.coordinate ?? snapshotSubject.value?.currentCoordinate
        guard let startCoordinate else { return }

        clearPendingNextTrip()

        let session = TripSession(
            startCoordinate: startCoordinate,
            destinationCoordinate: CLLocationCoordinate2D(latitude: nextItem.latitude, longitude: nextItem.longitude),
            leadTimeMinutes: nextItem.leadTimeMinutes,
            selectedJourneyMode: nextItem.selectedJourneyMode,
            journeyPlanItemID: nextItem.id,
            startedAt: .now
        )
        start(session: session)
    }

    func clearPendingNextTrip() {
        guard let seed = loadPendingNextTripSeed() else {
            defaults?.removeObject(forKey: AppConstants.pendingNextTripSeedKey)
            return
        }
        promptService.cancelNextTripPrompt(planItemID: seed.planItemID)
        defaults?.removeObject(forKey: AppConstants.pendingNextTripSeedKey)
    }

    func refreshFromBackground() {
        guard sessionSubject.value != nil else { return }
        guard runState == .active else {
            backgroundTaskScheduler.scheduleRefresh()
            return
        }
        locationService.requestOneTimeLocation()
        if let location = locationService.currentLocation {
            scheduleEstimate(for: location)
        }
        backgroundTaskScheduler.scheduleRefresh()
    }

    private struct PendingNextTripSeed: Codable, Equatable {
        let planItemID: UUID
        let tripTitle: String
        let fireAt: Date
    }

    private func savePendingNextTripSeed(_ seed: PendingNextTripSeed) {
        guard let defaults else { return }
        guard let encoded = try? encoder.encode(seed) else { return }
        defaults.set(encoded, forKey: AppConstants.pendingNextTripSeedKey)
    }

    private func loadPendingNextTripSeed() -> PendingNextTripSeed? {
        guard let defaults else { return nil }
        guard let data = defaults.data(forKey: AppConstants.pendingNextTripSeedKey) else { return nil }
        return try? decoder.decode(PendingNextTripSeed.self, from: data)
    }

    private func bindLocationUpdates() {
        locationService.locationPublisher
            .sink { [weak self] location in
                guard let self else { return }
                guard self.sessionSubject.value != nil else { return }
                self.scheduleEstimate(for: location)
            }
            .store(in: &cancellables)
    }

    private func bindAuthorizationUpdates() {
        locationService.authorizationStatusPublisher
            .sink { [weak self] status in
                guard let self, self.sessionSubject.value != nil else { return }
                if status == .denied || status == .restricted {
                    self.completeAndStop(
                        status: .locationTurnedOffBeforeDestination,
                        finalSnapshot: self.snapshotSubject.value
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func bindAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isInBackground = true
                if self.sessionSubject.value != nil {
                    self.locationService.stopStandardUpdates()
                    self.stopIntervalChecks()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isInBackground = false
                if self.sessionSubject.value != nil, self.runState == .active {
                    self.locationService.startStandardUpdates()
                    self.startIntervalChecks()
                }
            }
            .store(in: &cancellables)
    }

    private func startIntervalChecks() {
        intervalCancellable?.cancel()
        guard runState == .active else { return }

        intervalCancellable = Timer.publish(every: intervalCheckSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.sessionSubject.value != nil else { return }
                guard self.runState == .active else { return }
                if let location = self.locationService.currentLocation,
                   abs(location.timestamp.timeIntervalSinceNow) < 180 {
                    self.scheduleEstimate(for: location)
                } else {
                    self.locationService.requestOneTimeLocation()
                }
            }
    }

    private func stopIntervalChecks() {
        intervalCancellable?.cancel()
        intervalCancellable = nil
    }

    private func scheduleEstimate(for location: CLLocation, forceRouteEstimate: Bool = false) {
        estimateTask?.cancel()
        estimateTask = Task { [weak self] in
            await self?.process(location: location, forceRouteEstimate: forceRouteEstimate)
        }
    }

    private func destinationRegionRadius(for leadTimeMinutes: Int) -> CLLocationDistance {
        let speedMetersPerSecond = 9.72 // ~35 km/h fallback average
        let estimatedMeters = Double(leadTimeMinutes) * 60 * speedMetersPerSecond
        return min(max(estimatedMeters, 600), 4000)
    }

    private func process(location: CLLocation, forceRouteEstimate: Bool = false) async {
        guard let session = sessionSubject.value else { return }
        let sessionID = session.id

        let detectedActivity = detectJourneyActivity(at: location, previous: lastMovementLocation)
        latestDetectedActivity = detectedActivity

        let movedMeaningfully = isMeaningfulMovement(
            location: location,
            previousLocation: lastMovementLocation,
            detectedActivity: detectedActivity
        )

        if movedMeaningfully {
            lastMovementDetectedAt = Date()
            lastMovementLocation = location
            if runState == .atRest {
                resumeActiveMonitoring(session: session, from: location)
            }
        }

        if runState == .active, !movedMeaningfully {
            let lastMove = lastMovementDetectedAt ?? session.startedAt
            if Date().timeIntervalSince(lastMove) >= idleTimeoutSeconds {
                enterRestState(session: session, latestLocation: location)
            }
        }

        if runState == .atRest, !movedMeaningfully, !forceRouteEstimate {
            publishRestSnapshot(session: session, location: location)
            return
        }

        let rawEstimate = await etaEstimator.estimateETA(
            from: location,
            to: session.destinationCoordinate,
            mode: session.selectedJourneyMode
        )
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
        } else if forceRouteEstimate {
            estimate = ETAEstimate(
                distanceMeters: max(0, rawEstimate.distanceMeters),
                etaSeconds: max(0, rawEstimate.etaSeconds)
            )
        } else {
            estimate = stabilizeEstimateIfStationary(rawEstimate, at: location)
        }

        if !hasScheduledProgressNotifications,
           estimate.etaSeconds > 0,
           !hasReachedDestination {
            hasScheduledProgressNotifications = true
            let tripTitle = session.journeyPlanItemID.flatMap { journeyPlanItemID in
                journeyPlanSubject.value.first(where: { $0.id == journeyPlanItemID })?.title
            }
            progressNotificationService.scheduleQuarterProgressNotifications(
                sessionID: session.id,
                tripTitle: tripTitle,
                startedAt: session.startedAt,
                estimatedDurationSeconds: estimate.etaSeconds
            )
        }

        let snapshot = TravelSnapshot(
            currentCoordinate: location.coordinate,
            distanceMeters: estimate.distanceMeters,
            etaSeconds: estimate.etaSeconds,
            detectedActivity: detectedActivity,
            monitoringState: runState,
            updatedAt: .now
        )

        appendRoutePointIfNeeded(
            latitude: snapshot.currentCoordinate.latitude,
            longitude: snapshot.currentCoordinate.longitude,
            timestamp: snapshot.updatedAt,
            forceAppend: hasReachedDestination
        )

        snapshotSubject.send(snapshot)
        widgetSyncService.sync(snapshot: snapshot, session: session)
        await updateLiveActivity(for: session, snapshot: snapshot)
        recordActivityEvent(
            status: liveActivityStatusText(for: session, snapshot: snapshot),
            latitude: snapshot.currentCoordinate.latitude,
            longitude: snapshot.currentCoordinate.longitude,
            timestamp: snapshot.updatedAt
        )
        persistActiveSession(session)

        if hasReachedDestination {
            promptService.notifyDestinationReached(sessionID: session.id)
            NextTripPromptCenter.postTripVoicePromptRequested(message: "You’ve reached your destination.")
            completeAndStop(status: .destinationReached, finalSnapshot: snapshot)
            return
        }

        let leadTimeSeconds = TimeInterval(session.leadTimeMinutes * 60)
        if !hasTriggeredFakeCall && estimate.etaSeconds <= leadTimeSeconds {
            hasTriggeredFakeCall = true
            promptService.notifyLeadTime(sessionID: session.id, etaMinutes: snapshot.etaMinutes)
            NextTripPromptCenter.postTripVoicePromptRequested(
                message: "Your destination is close. ETA is about \(snapshot.etaMinutes) minute(s)."
            )
        }
    }

    private func detectJourneyActivity(at location: CLLocation, previous: CLLocation?) -> DetectedJourneyActivity {
        activityDetector.detect(at: location, previous: previous)
    }

    private func isMeaningfulMovement(
        location: CLLocation,
        previousLocation: CLLocation?,
        detectedActivity: DetectedJourneyActivity
    ) -> Bool {
        if detectedActivity == .walking || detectedActivity == .running || detectedActivity == .climbing {
            return true
        }

        guard let previousLocation else { return false }

        let movedMeters = location.distance(from: previousLocation)
        let dynamicThreshold = max(12, min(30, location.horizontalAccuracy * 0.6))
        let speed = max(location.speed, 0)

        return movedMeters >= dynamicThreshold || speed >= 1.0
    }

    private func enterRestState(session: TripSession, latestLocation: CLLocation) {
        guard runState != .atRest else { return }

        runState = .atRest
        locationService.stopStandardUpdates()
        stopIntervalChecks()
        recordActivityEvent(
            status: "Idle / At Rest",
            latitude: latestLocation.coordinate.latitude,
            longitude: latestLocation.coordinate.longitude,
            timestamp: Date()
        )
        publishRestSnapshot(session: session, location: latestLocation)
        persistActiveSession(session)
    }

    private func resumeActiveMonitoring(session: TripSession, from location: CLLocation) {
        guard runState != .active else { return }

        runState = .active
        if !isInBackground {
            locationService.startStandardUpdates()
            locationService.requestOneTimeLocation()
            startIntervalChecks()
        }
        recordActivityEvent(
            status: "Monitoring resumed",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: Date()
        )

        if let previousSnapshot = snapshotSubject.value {
            let snapshot = TravelSnapshot(
                currentCoordinate: location.coordinate,
                distanceMeters: previousSnapshot.distanceMeters,
                etaSeconds: previousSnapshot.etaSeconds,
                detectedActivity: latestDetectedActivity,
                monitoringState: .active,
                updatedAt: .now
            )
            snapshotSubject.send(snapshot)
            widgetSyncService.sync(snapshot: snapshot, session: session)
        }

        persistActiveSession(session)
    }

    private func publishRestSnapshot(session: TripSession, location: CLLocation) {
        let destination = CLLocation(
            latitude: session.destinationCoordinate.latitude,
            longitude: session.destinationCoordinate.longitude
        )

        let previousSnapshot = snapshotSubject.value
        let snapshot = TravelSnapshot(
            currentCoordinate: location.coordinate,
            distanceMeters: previousSnapshot?.distanceMeters ?? max(0, location.distance(from: destination)),
            etaSeconds: previousSnapshot?.etaSeconds ?? 0,
            detectedActivity: .stationary,
            monitoringState: .atRest,
            updatedAt: .now
        )
        snapshotSubject.send(snapshot)
        widgetSyncService.sync(snapshot: snapshot, session: session)
        recordActivityEvent(
            status: "Idle / At Rest",
            latitude: snapshot.currentCoordinate.latitude,
            longitude: snapshot.currentCoordinate.longitude,
            timestamp: snapshot.updatedAt
        )
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

    private func appendRoutePointIfNeeded(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        forceAppend: Bool = false
    ) {
        let newPoint = PersistedTrackPoint(latitude: latitude, longitude: longitude, timestamp: timestamp)

        guard let lastPoint = currentRoutePoints.last else {
            currentRoutePoints.append(newPoint)
            return
        }

        if forceAppend {
            currentRoutePoints.append(newPoint)
            return
        }

        let previous = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
        let current = CLLocation(latitude: latitude, longitude: longitude)
        let movedMeters = current.distance(from: previous)
        let elapsed = timestamp.timeIntervalSince(lastPoint.timestamp)

        guard movedMeters >= routePointMinimumDistanceMeters || elapsed >= routePointMinimumIntervalSeconds else {
            return
        }

        currentRoutePoints.append(newPoint)
    }

    private func recordActivityEvent(
        status: String,
        latitude: Double?,
        longitude: Double?,
        timestamp: Date
    ) {
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStatus.isEmpty else { return }

        if let last = currentActivityEvents.last {
            let sameStatus = last.status == trimmedStatus
            let sameLocation = last.latitude == latitude && last.longitude == longitude
            let closeInTime = timestamp.timeIntervalSince(last.timestamp) < 2
            if sameStatus && sameLocation && closeInTime {
                return
            }
        }

        currentActivityEvents.append(
            TripActivityEvent(
                status: trimmedStatus,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
        )

        if currentActivityEvents.count > maxActivityEventsPerSession {
            currentActivityEvents.removeFirst(currentActivityEvents.count - maxActivityEventsPerSession)
        }
    }

    private func resolvedManualStopStatus() -> JourneyCompletionStatus {
        if hasReachedDestination {
            return .journeyFinished
        }
        if let snapshot = snapshotSubject.value,
           snapshot.distanceMeters <= AppConstants.arrivalDistanceThresholdMeters {
            return .journeyFinished
        }
        return .cancelledByUser
    }

    private func completeAndStop(status: JourneyCompletionStatus, finalSnapshot: TravelSnapshot?) {
        guard let activeSession = sessionSubject.value else {
            clearRuntimeState()
            return
        }

        let endedAt = Date()
        let finalCoordinate = finalSnapshot?.currentCoordinate ?? locationService.currentLocation?.coordinate
        recordActivityEvent(
            status: status.title,
            latitude: finalCoordinate?.latitude,
            longitude: finalCoordinate?.longitude,
            timestamp: endedAt
        )
        if let finalSnapshot {
            appendRoutePointIfNeeded(
                latitude: finalSnapshot.currentCoordinate.latitude,
                longitude: finalSnapshot.currentCoordinate.longitude,
                timestamp: finalSnapshot.updatedAt,
                forceAppend: true
            )
        } else if let currentLocation = locationService.currentLocation {
            appendRoutePointIfNeeded(
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                timestamp: endedAt,
                forceAppend: true
            )
        }

        let gpxResult = writeGPXFile(session: activeSession, endedAt: endedAt, points: currentRoutePoints)
        let historySession = TripHistorySession(
            id: activeSession.id,
            startedAt: activeSession.startedAt,
            endedAt: endedAt,
            startLatitude: activeSession.startCoordinate.latitude,
            startLongitude: activeSession.startCoordinate.longitude,
            destinationLatitude: activeSession.destinationCoordinate.latitude,
            destinationLongitude: activeSession.destinationCoordinate.longitude,
            pointsCount: currentRoutePoints.count,
            gpxFileName: gpxResult.fileName,
            gpxFilePath: gpxResult.filePath,
            completionStatus: status,
            selectedJourneyMode: activeSession.selectedJourneyMode,
            finalDetectedActivity: latestDetectedActivity,
            activityEvents: currentActivityEvents
        )
        appendToHistory(historySession)

        prepareNextTripPromptIfNeeded(
            activeSession: activeSession,
            completionStatus: status,
            finalSnapshot: finalSnapshot,
            endedAt: endedAt
        )

        clearRuntimeState()
        clearPersistedActiveSession()
        widgetSyncService.clearActiveTrip()

        Task { [weak self] in
            await self?.endLiveActivity()
        }
    }

    private func clearRuntimeState() {
        sessionSubject.send(nil)
        snapshotSubject.send(nil)
        hasTriggeredFakeCall = false
        hasReachedDestination = false
        runState = .active

        estimateTask?.cancel()
        estimateTask = nil
        stopIntervalChecks()

        if let progressNotificationSessionID {
            progressNotificationService.cancelQuarterProgressNotifications(sessionID: progressNotificationSessionID)
        }
        hasScheduledProgressNotifications = false
        progressNotificationSessionID = nil
        locationService.stopUpdates()

        currentRoutePoints.removeAll(keepingCapacity: false)
        currentActivityEvents.removeAll(keepingCapacity: false)
        lastMovementDetectedAt = nil
        lastMovementLocation = nil
        latestDetectedActivity = .unknown
        lastLiveActivityState = nil
        lastLiveActivityUpdateAt = nil
    }

    private func prepareNextTripPromptIfNeeded(
        activeSession: TripSession,
        completionStatus: JourneyCompletionStatus,
        finalSnapshot: TravelSnapshot?,
        endedAt: Date
    ) {
        guard activeSession.journeyPlanItemID != nil else { return }

        finalizeJourneyPlanItemStatus(for: activeSession, completionStatus: completionStatus, endedAt: endedAt)
        guard shouldAdvanceJourneyPlan(after: completionStatus) else { return }

        let calendar = Calendar.current
        let candidates = journeyPlanSubject.value
            .filter { calendar.isDate($0.plannedStartAt, inSameDayAs: endedAt) }
            .filter { $0.status == .started }
            .sorted { lhs, rhs in
                if lhs.plannedStartAt == rhs.plannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.plannedStartAt < rhs.plannedStartAt
            }

        guard let nextItem = candidates.first(where: { $0.plannedStartAt >= endedAt }) ?? candidates.first else {
            return
        }

        let fireAt = max(nextItem.plannedStartAt, endedAt)
        let seed = PendingNextTripSeed(planItemID: nextItem.id, tripTitle: nextItem.title, fireAt: fireAt)
        savePendingNextTripSeed(seed)
        promptService.scheduleNextTripPrompt(planItemID: nextItem.id, tripTitle: nextItem.title, fireAt: fireAt)
        NextTripPromptCenter.postNextTripPromptScheduled(planItemID: nextItem.id, tripTitle: nextItem.title, fireAt: fireAt)

        if calendar.isDate(fireAt, inSameDayAs: endedAt),
           fireAt <= endedAt.addingTimeInterval(2) {
            NextTripPromptCenter.postTripVoicePromptRequested(message: "Start next trip to \(nextItem.title) now?")
        }
    }

    private func handleExternalDataDeletion() {
        estimateTask?.cancel()
        estimateTask = nil
        stopIntervalChecks()
        locationService.stopUpdates()

        currentRoutePoints.removeAll(keepingCapacity: false)
        currentActivityEvents.removeAll(keepingCapacity: false)
        hasTriggeredFakeCall = false
        hasReachedDestination = false
        runState = .active

        sessionSubject.send(nil)
        snapshotSubject.send(nil)
        historySubject.send([])
        journeyPlanSubject.send([])
        journeyPlanDeletedSubject.send([])

        clearPersistedActiveSession()
        widgetSyncService.clearActiveTrip()
        Task { [weak self] in
            await self?.endLiveActivity()
        }
    }

    private func resolvedSessionForStart(_ session: TripSession) -> TripSession {
        guard session.journeyPlanItemID == nil else { return session }
        guard let matchedItem = matchingJourneyPlanItem(for: session) else { return session }

        return TripSession(
            id: session.id,
            startCoordinate: session.startCoordinate,
            destinationCoordinate: session.destinationCoordinate,
            leadTimeMinutes: session.leadTimeMinutes,
            selectedJourneyMode: session.selectedJourneyMode,
            journeyPlanItemID: matchedItem.id,
            startedAt: session.startedAt
        )
    }

    private func matchingJourneyPlanItem(for session: TripSession) -> JourneyPlanItem? {
        let destination = CLLocation(
            latitude: session.destinationCoordinate.latitude,
            longitude: session.destinationCoordinate.longitude
        )

        return journeyPlanSubject.value
            .filter { item in
                item.status == .started &&
                item.selectedJourneyMode == session.selectedJourneyMode &&
                Calendar.current.isDate(item.userPlannedStartAt, inSameDayAs: session.startedAt)
            }
            .filter { item in
                let itemLocation = CLLocation(latitude: item.latitude, longitude: item.longitude)
                return itemLocation.distance(from: destination) <= journeyPlanMatchDistanceMeters
            }
            .sorted { lhs, rhs in
                let lhsTimeDelta = abs(lhs.plannedStartAt.timeIntervalSince(session.startedAt))
                let rhsTimeDelta = abs(rhs.plannedStartAt.timeIntervalSince(session.startedAt))
                if lhsTimeDelta == rhsTimeDelta {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhsTimeDelta < rhsTimeDelta
            }
            .first
    }

    private func startLiveActivity(for session: TripSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        TripMonitoringRepositoryImpl.liveActivityStartQueue.sync {
            attachToExistingLiveActivityIfAvailable()
            if liveActivity != nil { return }

            let attributes = TravelAssistWidgetAttributes(name: "TravelAssist")
            let modePresentation = liveActivityModePresentation(for: session, snapshot: nil)
            let initialState = TravelAssistWidgetAttributes.ContentState(
                etaMinutes: max(session.leadTimeMinutes, 1),
                statusText: session.selectedJourneyMode.progressStatusText,
                progress: 0,
                distanceText: "--",
                modeSymbolName: modePresentation.symbolName,
                modeTitle: modePresentation.title
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
                defaults?.set(liveActivity?.id, forKey: StorageKeys.liveActivityID)
                lastLiveActivityState = initialState
                lastLiveActivityUpdateAt = Date()
            } catch {
                liveActivity = nil
            }
        }

        if let liveActivity {
            let modePresentation = liveActivityModePresentation(for: session, snapshot: nil)
            let initialState = TravelAssistWidgetAttributes.ContentState(
                etaMinutes: max(session.leadTimeMinutes, 1),
                statusText: session.selectedJourneyMode.progressStatusText,
                progress: 0,
                distanceText: "--",
                modeSymbolName: modePresentation.symbolName,
                modeTitle: modePresentation.title
            )
            let content = ActivityContent(
                state: initialState,
                staleDate: Date().addingTimeInterval(120)
            )
            Task { [weak self] in
                await liveActivity.update(content)
                self?.lastLiveActivityState = initialState
                self?.lastLiveActivityUpdateAt = Date()
            }
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
        let modePresentation = liveActivityModePresentation(for: session, snapshot: snapshot)
        let state = TravelAssistWidgetAttributes.ContentState(
            etaMinutes: max(snapshot.etaMinutes, 0),
            statusText: statusText,
            progress: progress,
            distanceText: liveActivityDistanceText(snapshot.distanceMeters),
            modeSymbolName: modePresentation.symbolName,
            modeTitle: modePresentation.title
        )
        guard shouldUpdateLiveActivity(with: state) else { return }
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(120)
        )
        await liveActivity.update(content)
        lastLiveActivityState = state
        lastLiveActivityUpdateAt = Date()
    }

    private func endLiveActivity() async {
        guard let liveActivity else { return }
        await liveActivity.end(nil, dismissalPolicy: .immediate)
        self.liveActivity = nil
        defaults?.removeObject(forKey: StorageKeys.liveActivityID)
        lastLiveActivityState = nil
        lastLiveActivityUpdateAt = nil
    }

    private func cleanupLiveActivitiesIfNoPersistedSession() {
        guard let defaults else { return }
        if defaults.data(forKey: StorageKeys.activeSession) != nil { return }
        if Activity<TravelAssistWidgetAttributes>.activities.isEmpty { return }

        defaults.removeObject(forKey: StorageKeys.liveActivityID)
        Task {
            for activity in Activity<TravelAssistWidgetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func attachToExistingLiveActivityIfAvailable() {
        guard liveActivity == nil else { return }

        let activities = Array(Activity<TravelAssistWidgetAttributes>.activities)
        guard let selected = selectLiveActivity(from: activities) else { return }

        liveActivity = selected
        defaults?.set(selected.id, forKey: StorageKeys.liveActivityID)

        if activities.count > 1 {
            let selectedID = selected.id
            Task {
                for activity in activities where activity.id != selectedID {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    private func selectLiveActivity(from activities: [Activity<TravelAssistWidgetAttributes>]) -> Activity<TravelAssistWidgetAttributes>? {
        guard !activities.isEmpty else { return nil }
        if let preferredID = defaults?.string(forKey: StorageKeys.liveActivityID),
           let preferred = activities.first(where: { $0.id == preferredID }) {
            return preferred
        }
        return activities.first
    }

    private func shouldUpdateLiveActivity(with state: TravelAssistWidgetAttributes.ContentState) -> Bool {
        guard let previousState = lastLiveActivityState,
              let lastLiveActivityUpdateAt else {
            return true
        }

        if state.statusText != previousState.statusText || state.modeTitle != previousState.modeTitle {
            return true
        }

        if state.etaMinutes != previousState.etaMinutes {
            return true
        }

        if abs(state.progress - previousState.progress) >= liveActivityMinimumProgressDelta {
            return true
        }

        return Date().timeIntervalSince(lastLiveActivityUpdateAt) >= liveActivityMinimumUpdateIntervalSeconds
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
        if snapshot.monitoringState == .atRest {
            return "Idle / At Rest"
        }
        if snapshot.distanceMeters <= AppConstants.arrivalDistanceThresholdMeters {
            return "Reached destination"
        }
        switch snapshot.detectedActivity {
        case .walking, .running, .climbing, .stationary:
            return snapshot.detectedActivity.progressStatusText
        case .unknown:
            break
        }
        if snapshot.etaMinutes <= session.leadTimeMinutes {
            return "Arriving soon"
        }
        return session.selectedJourneyMode.progressStatusText
    }

    private func liveActivityDistanceText(_ distanceMeters: CLLocationDistance) -> String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m remaining"
        }
        return String(format: "%.1f km remaining", distanceMeters / 1000)
    }

    private func liveActivityModePresentation(
        for session: TripSession,
        snapshot: TravelSnapshot?
    ) -> (symbolName: String, title: String) {
        guard let snapshot else {
            return (session.selectedJourneyMode.symbolName, session.selectedJourneyMode.title)
        }

        if snapshot.monitoringState == .atRest {
            return ("pause.circle", "At Rest")
        }

        switch snapshot.detectedActivity {
        case .walking, .running, .climbing:
            return (snapshot.detectedActivity.symbolName, snapshot.detectedActivity.title)
        case .stationary:
            return ("pause.circle", "At Rest")
        case .unknown:
            return (session.selectedJourneyMode.symbolName, session.selectedJourneyMode.title)
        }
    }

    private func persistActiveSession(_ session: TripSession) {
        guard let defaults else { return }
        let payload = PersistedActiveSession(
            id: session.id,
            startLatitude: session.startCoordinate.latitude,
            startLongitude: session.startCoordinate.longitude,
            destinationLatitude: session.destinationCoordinate.latitude,
            destinationLongitude: session.destinationCoordinate.longitude,
            leadTimeMinutes: session.leadTimeMinutes,
            selectedJourneyMode: session.selectedJourneyMode,
            journeyPlanItemID: session.journeyPlanItemID,
            startedAt: session.startedAt,
            routePoints: currentRoutePoints,
            activityEvents: currentActivityEvents,
            runState: runState,
            lastMovementDetectedAt: lastMovementDetectedAt,
            lastMovementLatitude: lastMovementLocation?.coordinate.latitude,
            lastMovementLongitude: lastMovementLocation?.coordinate.longitude,
            latestDetectedActivity: latestDetectedActivity
        )
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: StorageKeys.activeSession)
    }

    private func clearPersistedActiveSession() {
        defaults?.removeObject(forKey: StorageKeys.activeSession)
    }

    private func restoreActiveSessionIfNeeded() {
        guard let defaults,
              let data = defaults.data(forKey: StorageKeys.activeSession),
              let persisted = try? decoder.decode(PersistedActiveSession.self, from: data) else {
            return
        }

        let restoredSession = TripSession(
            id: persisted.id,
            startCoordinate: CLLocationCoordinate2D(latitude: persisted.startLatitude, longitude: persisted.startLongitude),
            destinationCoordinate: CLLocationCoordinate2D(latitude: persisted.destinationLatitude, longitude: persisted.destinationLongitude),
            leadTimeMinutes: persisted.leadTimeMinutes,
            selectedJourneyMode: persisted.selectedJourneyMode,
            journeyPlanItemID: persisted.journeyPlanItemID,
            startedAt: persisted.startedAt
        )

        currentRoutePoints = persisted.routePoints
        currentActivityEvents = persisted.activityEvents ?? []
        runState = persisted.runState
        lastMovementDetectedAt = persisted.lastMovementDetectedAt
        latestDetectedActivity = persisted.latestDetectedActivity
        if let lat = persisted.lastMovementLatitude, let lon = persisted.lastMovementLongitude {
            lastMovementLocation = CLLocation(latitude: lat, longitude: lon)
        }

        sessionSubject.send(restoredSession)

        if let persistedSnapshot = loadPersistedSnapshot(with: runState) {
            snapshotSubject.send(persistedSnapshot)
        }

        widgetSyncService.sync(
            snapshot: snapshotSubject.value,
            session: restoredSession
        )
        widgetSyncService.syncJourneyPlan(journeyPlanSubject.value)

        locationService.requestPermissionsIfNeeded()
        if runState == .active {
            locationService.startStandardUpdates()
            locationService.requestOneTimeLocation()
            startIntervalChecks()
        } else {
            locationService.stopStandardUpdates()
            stopIntervalChecks()
        }

        locationService.startSignificantUpdates()
        locationService.startMonitoringDestination(
            coordinate: restoredSession.destinationCoordinate,
            radius: destinationRegionRadius(for: restoredSession.leadTimeMinutes)
        )
        startLiveActivity(for: restoredSession)
        backgroundTaskScheduler.scheduleRefresh()

        if runState == .active, let location = locationService.currentLocation {
            scheduleEstimate(for: location)
        }
    }

    private func loadPersistedSnapshot(with runState: MonitoringRunState) -> TravelSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: "widget.snapshot"),
              let dto = try? decoder.decode(TravelWidgetSnapshotDTO.self, from: data) else {
            return nil
        }

        let detectedActivity = dto.detectedActivityRaw
            .flatMap(DetectedJourneyActivity.init(rawValue:))
            ?? .unknown
        let snapshotRunState = dto.monitoringStateRaw
            .flatMap(MonitoringRunState.init(rawValue:))
            ?? runState

        return TravelSnapshot(
            currentCoordinate: CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude),
            distanceMeters: dto.distanceMeters,
            etaSeconds: dto.etaSeconds,
            detectedActivity: detectedActivity,
            monitoringState: snapshotRunState,
            updatedAt: dto.updatedAt
        )
    }

    private func appendToHistory(_ session: TripHistorySession) {
        var updated = historySubject.value
        updated.insert(session, at: 0)
        if updated.count > 100 {
            updated = Array(updated.prefix(100))
        }
        historySubject.send(updated)
        persistHistory(updated)
    }

    private func loadPersistedHistory() {
        guard let defaults,
              let data = defaults.data(forKey: StorageKeys.historySessions),
              let persisted = try? decoder.decode([PersistedHistorySession].self, from: data) else {
            historySubject.send([])
            return
        }

        historySubject.send(persisted.map { $0.domain })
    }

	    private func loadPersistedJourneyPlan() {
	        guard let defaults,
	              let data = defaults.data(forKey: StorageKeys.journeyPlanItems),
	              let persisted = try? decoder.decode([JourneyPlanItem].self, from: data) else {
	            journeyPlanSubject.send([])
	            return
	        }

	        let filtered = applyDeletions(to: persisted, deletions: journeyPlanDeletedSubject.value)

	        journeyPlanSubject.send(
	            filtered.sorted { lhs, rhs in
	                if lhs.plannedStartAt == rhs.plannedStartAt {
	                    return lhs.createdAt < rhs.createdAt
	                }
	                return lhs.plannedStartAt < rhs.plannedStartAt
	            }
	        )
	    }

	    private func loadPersistedJourneyPlanDeletions() {
	        guard let defaults,
	              let data = defaults.data(forKey: StorageKeys.journeyPlanDeleted),
	              let persisted = try? decoder.decode([JourneyPlanTombstone].self, from: data) else {
	            journeyPlanDeletedSubject.send([])
	            return
	        }
	        journeyPlanDeletedSubject.send(pruneJourneyPlanDeletions(persisted))
	    }

    private func persistHistory(_ sessions: [TripHistorySession]) {
        guard let defaults else { return }
        let persisted = sessions.map(PersistedHistorySession.init)
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: StorageKeys.historySessions)
    }

    func mergeHistoryFromICloud(_ remoteSessions: [TripHistorySession]) {
        guard !remoteSessions.isEmpty else { return }

        let local = historySubject.value
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        var mergedByID: [UUID: TripHistorySession] = localByID
        for remote in remoteSessions {
            if let existing = mergedByID[remote.id] {
                // Keep local GPX path if we have one.
                let keptPath = existing.gpxFilePath
                mergedByID[remote.id] = TripHistorySession(
                    id: remote.id,
                    startedAt: remote.startedAt,
                    endedAt: remote.endedAt,
                    startLatitude: remote.startLatitude,
                    startLongitude: remote.startLongitude,
                    destinationLatitude: remote.destinationLatitude,
                    destinationLongitude: remote.destinationLongitude,
                    pointsCount: remote.pointsCount,
                    gpxFileName: remote.gpxFileName.isEmpty ? existing.gpxFileName : remote.gpxFileName,
                    gpxFilePath: keptPath,
                    completionStatus: remote.completionStatus,
                    selectedJourneyMode: remote.selectedJourneyMode,
                    finalDetectedActivity: remote.finalDetectedActivity,
                    activityEvents: remote.activityEvents.isEmpty ? existing.activityEvents : remote.activityEvents
                )
            } else {
                mergedByID[remote.id] = remote
            }
        }

        let merged = mergedByID.values
            .sorted { $0.startedAt > $1.startedAt }

        let limited = merged.count > 100 ? Array(merged.prefix(100)) : merged
        historySubject.send(limited)
        persistHistory(limited)
    }

    func currentHistorySessionsForSync() -> [TripHistorySession] {
        historySubject.value
    }

	    func mergeJourneyPlanFromICloud(
	        _ remoteItems: [JourneyPlanItem],
	        deleted remoteDeleted: [ICloudJourneyPlanSyncPayload.JourneyPlanTombstone] = []
	    ) {
	        guard !remoteItems.isEmpty || !remoteDeleted.isEmpty else { return }

	        let local = journeyPlanSubject.value
	        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

	        var tombstonesByID = Dictionary(uniqueKeysWithValues: journeyPlanDeletedSubject.value.map { ($0.id, $0) })
	        for remote in remoteDeleted {
	            let tombstone = JourneyPlanTombstone(id: remote.id, deletedAt: remote.deletedAt)
	            if let existing = tombstonesByID[tombstone.id] {
	                tombstonesByID[tombstone.id] = tombstone.deletedAt > existing.deletedAt ? tombstone : existing
	            } else {
	                tombstonesByID[tombstone.id] = tombstone
	            }
	        }

	        var mergedByID: [UUID: JourneyPlanItem] = localByID
	        for remote in remoteItems {
	            if let existing = mergedByID[remote.id] {
	                mergedByID[remote.id] = remote.updatedAt > existing.updatedAt ? remote : existing
	            } else {
	                mergedByID[remote.id] = remote
	            }
	        }

	        let deletions = pruneJourneyPlanDeletions(Array(tombstonesByID.values))
	        let deletedAtByID = Dictionary(uniqueKeysWithValues: deletions.map { ($0.id, $0.deletedAt) })
	        mergedByID = mergedByID.filter { id, item in
	            guard let deletedAt = deletedAtByID[id] else { return true }
	            return item.updatedAt > deletedAt
	        }

	        let survivingIDs = Set(mergedByID.keys)
	        let cleanedTombstones = deletions.filter { tombstone in
	            guard survivingIDs.contains(tombstone.id) else { return true }
	            guard let item = mergedByID[tombstone.id] else { return true }
	            return tombstone.deletedAt >= item.updatedAt
	        }

	        journeyPlanDeletedSubject.send(cleanedTombstones)
	        persistJourneyPlanDeletions(cleanedTombstones)

	        let merged = mergedByID.values
	            .sorted { lhs, rhs in
	                if lhs.plannedStartAt == rhs.plannedStartAt {
	                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.plannedStartAt < rhs.plannedStartAt
            }

	        let limited = merged.count > 500 ? Array(merged.prefix(500)) : merged
	        saveJourneyPlanItems(limited)
	    }

	    func currentJourneyPlanItemsForSync() -> [JourneyPlanItem] {
	        journeyPlanSubject.value
	    }

	    func currentJourneyPlanTombstonesForSync() -> [JourneyPlanTombstone] {
	        journeyPlanDeletedSubject.value
	    }

    func updateHistorySessionGPXPath(id: UUID, path: String) {
        guard !path.isEmpty else { return }
        var updated = historySubject.value
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let existing = updated[index]
        guard existing.gpxFilePath != path else { return }

        updated[index] = TripHistorySession(
            id: existing.id,
            startedAt: existing.startedAt,
            endedAt: existing.endedAt,
            startLatitude: existing.startLatitude,
            startLongitude: existing.startLongitude,
            destinationLatitude: existing.destinationLatitude,
            destinationLongitude: existing.destinationLongitude,
            pointsCount: existing.pointsCount,
            gpxFileName: existing.gpxFileName,
            gpxFilePath: path,
            completionStatus: existing.completionStatus,
            selectedJourneyMode: existing.selectedJourneyMode,
            finalDetectedActivity: existing.finalDetectedActivity,
            activityEvents: existing.activityEvents
        )

        historySubject.send(updated)
        persistHistory(updated)
    }

	    private func persistJourneyPlan(_ items: [JourneyPlanItem]) {
	        guard let defaults else { return }
	        guard let data = try? encoder.encode(items) else { return }
	        defaults.set(data, forKey: StorageKeys.journeyPlanItems)
	    }

	    private func persistJourneyPlanDeletions(_ tombstones: [JourneyPlanTombstone]) {
	        guard let defaults else { return }
	        guard let data = try? encoder.encode(tombstones) else { return }
	        defaults.set(data, forKey: StorageKeys.journeyPlanDeleted)
	    }

	    private func saveJourneyPlanItems(_ items: [JourneyPlanItem]) {
	        let filtered = applyDeletions(to: items, deletions: journeyPlanDeletedSubject.value)
	        journeyPlanSubject.send(filtered)
	        syncActiveSessionIfNeeded(with: filtered)
	        persistJourneyPlan(filtered)
	        widgetSyncService.syncJourneyPlan(filtered)

        if let seed = loadPendingNextTripSeed(),
           !filtered.contains(where: { $0.id == seed.planItemID }) {
            clearPendingNextTrip()
        }
	    }

	    private func applyDeletions(to items: [JourneyPlanItem], deletions: [JourneyPlanTombstone]) -> [JourneyPlanItem] {
	        guard !deletions.isEmpty else { return items }
	        let deletedByID = Dictionary(uniqueKeysWithValues: deletions.map { ($0.id, $0.deletedAt) })
	        return items.filter { item in
	            guard let deletedAt = deletedByID[item.id] else { return true }
	            return item.updatedAt > deletedAt
	        }
	    }

	    private func recordDeletions(from old: [JourneyPlanItem], to new: [JourneyPlanItem], deletedAt: Date) {
	        let newIDs = Set(new.map(\.id))
	        let removed = old.filter { !newIDs.contains($0.id) }.map(\.id)
	        guard !removed.isEmpty else { return }

	        var tombstonesByID = Dictionary(uniqueKeysWithValues: journeyPlanDeletedSubject.value.map { ($0.id, $0) })
	        for id in removed {
	            let tombstone = JourneyPlanTombstone(id: id, deletedAt: deletedAt)
	            if let existing = tombstonesByID[id] {
	                if tombstone.deletedAt > existing.deletedAt {
	                    tombstonesByID[id] = tombstone
	                }
	            } else {
	                tombstonesByID[id] = tombstone
	            }
	        }

	        let pruned = pruneJourneyPlanDeletions(Array(tombstonesByID.values))
	        journeyPlanDeletedSubject.send(pruned)
	        persistJourneyPlanDeletions(pruned)
	    }

	    private func clearDeletionIfRevived(itemID: UUID, itemUpdatedAt: Date) {
	        var tombstones = journeyPlanDeletedSubject.value
	        guard let index = tombstones.firstIndex(where: { $0.id == itemID }) else { return }
	        guard itemUpdatedAt > tombstones[index].deletedAt else { return }
	        tombstones.remove(at: index)
	        journeyPlanDeletedSubject.send(tombstones)
	        persistJourneyPlanDeletions(tombstones)
	    }

	    private func pruneJourneyPlanDeletions(_ tombstones: [JourneyPlanTombstone]) -> [JourneyPlanTombstone] {
	        let cutoff = Date().addingTimeInterval(-180 * 24 * 60 * 60) // 180 days
	        let recent = tombstones.filter { $0.deletedAt >= cutoff }
	        let sorted = recent.sorted { $0.deletedAt > $1.deletedAt }
	        return sorted.count > 500 ? Array(sorted.prefix(500)) : sorted
	    }

    private func syncActiveSessionIfNeeded(with items: [JourneyPlanItem]) {
        guard let activeSession = sessionSubject.value,
              let journeyPlanItemID = activeSession.journeyPlanItemID,
              let updatedItem = items.first(where: { $0.id == journeyPlanItemID }) else {
            return
        }

        let updatedDestination = CLLocationCoordinate2D(
            latitude: updatedItem.latitude,
            longitude: updatedItem.longitude
        )

        let hasDestinationChanged =
            abs(activeSession.destinationCoordinate.latitude - updatedDestination.latitude) >= 0.000001 ||
            abs(activeSession.destinationCoordinate.longitude - updatedDestination.longitude) >= 0.000001
        let hasJourneyModeChanged = activeSession.selectedJourneyMode != updatedItem.selectedJourneyMode
        let hasLeadTimeChanged = activeSession.leadTimeMinutes != updatedItem.leadTimeMinutes

        guard hasDestinationChanged || hasJourneyModeChanged || hasLeadTimeChanged else {
            return
        }

        let updatedSession = TripSession(
            id: activeSession.id,
            startCoordinate: activeSession.startCoordinate,
            destinationCoordinate: updatedDestination,
            leadTimeMinutes: updatedItem.leadTimeMinutes,
            selectedJourneyMode: updatedItem.selectedJourneyMode,
            journeyPlanItemID: activeSession.journeyPlanItemID,
            startedAt: activeSession.startedAt
        )

        sessionSubject.send(updatedSession)
        persistActiveSession(updatedSession)
        locationService.startMonitoringDestination(
            coordinate: updatedSession.destinationCoordinate,
            radius: destinationRegionRadius(for: updatedSession.leadTimeMinutes)
        )

        if let snapshot = snapshotSubject.value {
            widgetSyncService.sync(snapshot: snapshot, session: updatedSession)
            Task { [weak self] in
                await self?.updateLiveActivity(for: updatedSession, snapshot: snapshot)
            }
        } else {
            widgetSyncService.sync(snapshot: nil, session: updatedSession)
        }

        if let currentLocation = locationService.currentLocation {
            scheduleEstimate(for: currentLocation, forceRouteEstimate: true)
        } else if let coordinate = snapshotSubject.value?.currentCoordinate {
            let fallbackLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            scheduleEstimate(for: fallbackLocation, forceRouteEstimate: true)
        }
    }

    private func updateJourneyPlanItemStatus(id: UUID, status: JourneyPlanStatus) {
        let updated = journeyPlanSubject.value.map { item in
            guard item.id == id else { return item }
            return JourneyPlanItem(
                id: item.id,
                roundTripGroupID: item.roundTripGroupID,
                title: item.title,
                subtitle: item.subtitle,
                startLatitude: item.startLatitude,
                startLongitude: item.startLongitude,
                latitude: item.latitude,
                longitude: item.longitude,
                userPlannedStartAt: item.userPlannedStartAt,
                plannedStartAt: item.plannedStartAt,
                approximateEndAt: item.approximateEndAt,
                estimatedTravelDurationSeconds: item.estimatedTravelDurationSeconds,
                selectedJourneyMode: item.selectedJourneyMode,
                leadTimeMinutes: item.leadTimeMinutes,
                status: status,
                createdAt: item.createdAt,
                updatedAt: .now
            )
        }
        saveJourneyPlanItems(updated)
    }

    private func markJourneyPlanItemInProgressAndRecomputeSchedule(id: UUID, startedAt: Date) {
        let calendar = Calendar.current
        guard let referenceItem = journeyPlanSubject.value.first(where: { $0.id == id }) else { return }
        let dayStart = calendar.startOfDay(for: referenceItem.userPlannedStartAt)

        var updated = journeyPlanSubject.value.map { item in
            guard item.id == id else { return item }
            return JourneyPlanItem(
                id: item.id,
                roundTripGroupID: item.roundTripGroupID,
                title: item.title,
                subtitle: item.subtitle,
                startLatitude: item.startLatitude,
                startLongitude: item.startLongitude,
                latitude: item.latitude,
                longitude: item.longitude,
                userPlannedStartAt: item.userPlannedStartAt,
                plannedStartAt: startedAt,
                estimatedTravelDurationSeconds: item.estimatedTravelDurationSeconds,
                selectedJourneyMode: item.selectedJourneyMode,
                leadTimeMinutes: item.leadTimeMinutes,
                status: .inProgress,
                createdAt: item.createdAt,
                updatedAt: .now
            )
        }

        updated = recomputeJourneyPlanSchedule(for: dayStart, items: updated)
        updated.sort { lhs, rhs in
            if lhs.plannedStartAt == rhs.plannedStartAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
        saveJourneyPlanItems(updated)
    }

    private func recomputeJourneyPlanSchedule(for dayStart: Date, items: [JourneyPlanItem]) -> [JourneyPlanItem] {
        let calendar = Calendar.current
        let targetItems = items
            .filter { calendar.isDate($0.userPlannedStartAt, inSameDayAs: dayStart) }
            .sorted { lhs, rhs in
                if lhs.userPlannedStartAt == rhs.userPlannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.userPlannedStartAt < rhs.userPlannedStartAt
            }

        var previousEndAt: Date?
        var previousDestinationCoordinate: CLLocationCoordinate2D?
        var shouldChainFromActualTimes = false
        var recalculatedByID = [UUID: JourneyPlanItem]()

        for item in targetItems {
            if item.status == .completed || item.status == .inProgress {
                recalculatedByID[item.id] = item
                previousEndAt = max(previousEndAt ?? item.approximateEndAt, item.approximateEndAt)
                previousDestinationCoordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
                if abs(item.plannedStartAt.timeIntervalSince(item.userPlannedStartAt)) >= 60 {
                    shouldChainFromActualTimes = true
                }
                continue
            }

            let adjustedStartAt: Date
            if let previousEndAt {
                adjustedStartAt = shouldChainFromActualTimes
                    ? previousEndAt
                    : max(previousEndAt, item.userPlannedStartAt)
            } else {
                adjustedStartAt = item.userPlannedStartAt
            }

            let recalculated = JourneyPlanItem(
                id: item.id,
                roundTripGroupID: item.roundTripGroupID,
                title: item.title,
                subtitle: item.subtitle,
                startLatitude: previousDestinationCoordinate?.latitude,
                startLongitude: previousDestinationCoordinate?.longitude,
                latitude: item.latitude,
                longitude: item.longitude,
                userPlannedStartAt: item.userPlannedStartAt,
                plannedStartAt: adjustedStartAt,
                estimatedTravelDurationSeconds: item.estimatedTravelDurationSeconds,
                selectedJourneyMode: item.selectedJourneyMode,
                leadTimeMinutes: item.leadTimeMinutes,
                status: item.status,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            recalculatedByID[item.id] = recalculated
            previousEndAt = recalculated.approximateEndAt
            previousDestinationCoordinate = CLLocationCoordinate2D(latitude: recalculated.latitude, longitude: recalculated.longitude)
        }

        return items.map { recalculatedByID[$0.id] ?? $0 }
    }

    private func finalizeJourneyPlanItemStatus(
        for activeSession: TripSession,
        completionStatus: JourneyCompletionStatus,
        endedAt: Date
    ) {
        let calendar = Calendar.current
        guard let journeyPlanItemID = activeSession.journeyPlanItemID,
              let referenceItem = journeyPlanSubject.value.first(where: { $0.id == journeyPlanItemID }) else {
            return
        }

        let dayStart = calendar.startOfDay(for: referenceItem.userPlannedStartAt)

        let updatedItem: JourneyPlanItem
        switch completionStatus {
        case .destinationReached, .journeyFinished:
            updatedItem = JourneyPlanItem(
                id: referenceItem.id,
                roundTripGroupID: referenceItem.roundTripGroupID,
                title: referenceItem.title,
                subtitle: referenceItem.subtitle,
                startLatitude: referenceItem.startLatitude,
                startLongitude: referenceItem.startLongitude,
                latitude: referenceItem.latitude,
                longitude: referenceItem.longitude,
                userPlannedStartAt: referenceItem.userPlannedStartAt,
                plannedStartAt: referenceItem.plannedStartAt,
                approximateEndAt: max(endedAt, referenceItem.plannedStartAt),
                estimatedTravelDurationSeconds: referenceItem.estimatedTravelDurationSeconds,
                selectedJourneyMode: referenceItem.selectedJourneyMode,
                leadTimeMinutes: referenceItem.leadTimeMinutes,
                status: .completed,
                createdAt: referenceItem.createdAt,
                updatedAt: .now
            )
        case .cancelledByUser, .locationTurnedOffBeforeDestination:
            updatedItem = JourneyPlanItem(
                id: referenceItem.id,
                roundTripGroupID: referenceItem.roundTripGroupID,
                title: referenceItem.title,
                subtitle: referenceItem.subtitle,
                startLatitude: referenceItem.startLatitude,
                startLongitude: referenceItem.startLongitude,
                latitude: referenceItem.latitude,
                longitude: referenceItem.longitude,
                userPlannedStartAt: referenceItem.userPlannedStartAt,
                plannedStartAt: referenceItem.userPlannedStartAt,
                estimatedTravelDurationSeconds: referenceItem.estimatedTravelDurationSeconds,
                selectedJourneyMode: referenceItem.selectedJourneyMode,
                leadTimeMinutes: referenceItem.leadTimeMinutes,
                status: .started,
                createdAt: referenceItem.createdAt,
                updatedAt: .now
            )
        }

        var updatedItems = journeyPlanSubject.value.map { item in
            item.id == journeyPlanItemID ? updatedItem : item
        }
        updatedItems = recomputeJourneyPlanSchedule(for: dayStart, items: updatedItems)
        updatedItems.sort { lhs, rhs in
            if lhs.plannedStartAt == rhs.plannedStartAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
        saveJourneyPlanItems(updatedItems)
    }

    private func shouldAdvanceJourneyPlan(after completionStatus: JourneyCompletionStatus) -> Bool {
        switch completionStatus {
        case .destinationReached, .journeyFinished:
            return true
        case .cancelledByUser, .locationTurnedOffBeforeDestination:
            return false
        }
    }

    private func writeGPXFile(
        session: TripSession,
        endedAt: Date,
        points: [PersistedTrackPoint]
    ) -> (fileName: String, filePath: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: endedAt)
        let fileName = "trip-\(timestamp)-\(session.id.uuidString.prefix(6)).gpx"

        let gpxString = buildGPX(session: session, endedAt: endedAt, points: points)
        guard let plainData = gpxString.data(using: .utf8) else {
            return (fileName, "")
        }
        let fileURL: URL
        do {
            fileURL = try gpxFileStore.localGPXURL(fileName: fileName)
        } catch {
            return (fileName, "")
        }

        do {
            let encrypted = try GPXFileCrypto.encrypt(plainData)
            try encrypted.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return (fileName, fileURL.path)
        } catch {
            return (fileName, "")
        }
    }

    private func buildGPX(session: TripSession, endedAt: Date, points: [PersistedTrackPoint]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let safePoints: [PersistedTrackPoint]
        if points.isEmpty {
            safePoints = [
                PersistedTrackPoint(
                    latitude: session.startCoordinate.latitude,
                    longitude: session.startCoordinate.longitude,
                    timestamp: session.startedAt
                ),
                PersistedTrackPoint(
                    latitude: session.destinationCoordinate.latitude,
                    longitude: session.destinationCoordinate.longitude,
                    timestamp: endedAt
                )
            ]
        } else {
            safePoints = points
        }

        let trkPoints = safePoints.map { point in
            "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(iso.string(from: point.timestamp))</time></trkpt>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TravelAssist" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <time>\(iso.string(from: session.startedAt))</time>
          </metadata>
          <trk>
            <name>TravelAssist session \(session.id.uuidString)</name>
            <trkseg>
              \(trkPoints)
            </trkseg>
          </trk>
        </gpx>
        """
    }
}

private struct PersistedTrackPoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

private struct PersistedActiveSession: Codable {
    let id: UUID
    let startLatitude: Double
    let startLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let leadTimeMinutes: Int
    let selectedJourneyMode: JourneyMode
    let journeyPlanItemID: UUID?
    let startedAt: Date
    let routePoints: [PersistedTrackPoint]
    let activityEvents: [TripActivityEvent]?
    let runState: MonitoringRunState
    let lastMovementDetectedAt: Date?
    let lastMovementLatitude: Double?
    let lastMovementLongitude: Double?
    let latestDetectedActivity: DetectedJourneyActivity

    private enum CodingKeys: String, CodingKey {
        case id
        case startLatitude
        case startLongitude
        case destinationLatitude
        case destinationLongitude
        case leadTimeMinutes
        case selectedJourneyMode
        case journeyPlanItemID
        case startedAt
        case routePoints
        case activityEvents
        case runState
        case lastMovementDetectedAt
        case lastMovementLatitude
        case lastMovementLongitude
        case latestDetectedActivity
    }

    init(
        id: UUID,
        startLatitude: Double,
        startLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double,
        leadTimeMinutes: Int,
        selectedJourneyMode: JourneyMode,
        journeyPlanItemID: UUID?,
        startedAt: Date,
        routePoints: [PersistedTrackPoint],
        activityEvents: [TripActivityEvent]?,
        runState: MonitoringRunState,
        lastMovementDetectedAt: Date?,
        lastMovementLatitude: Double?,
        lastMovementLongitude: Double?,
        latestDetectedActivity: DetectedJourneyActivity
    ) {
        self.id = id
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.leadTimeMinutes = leadTimeMinutes
        self.selectedJourneyMode = selectedJourneyMode
        self.journeyPlanItemID = journeyPlanItemID
        self.startedAt = startedAt
        self.routePoints = routePoints
        self.activityEvents = activityEvents
        self.runState = runState
        self.lastMovementDetectedAt = lastMovementDetectedAt
        self.lastMovementLatitude = lastMovementLatitude
        self.lastMovementLongitude = lastMovementLongitude
        self.latestDetectedActivity = latestDetectedActivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startLatitude = try container.decode(Double.self, forKey: .startLatitude)
        startLongitude = try container.decode(Double.self, forKey: .startLongitude)
        destinationLatitude = try container.decode(Double.self, forKey: .destinationLatitude)
        destinationLongitude = try container.decode(Double.self, forKey: .destinationLongitude)
        leadTimeMinutes = try container.decode(Int.self, forKey: .leadTimeMinutes)
        selectedJourneyMode = try container.decode(JourneyMode.self, forKey: .selectedJourneyMode)
        journeyPlanItemID = try container.decodeIfPresent(UUID.self, forKey: .journeyPlanItemID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        routePoints = try container.decodeIfPresent([PersistedTrackPoint].self, forKey: .routePoints) ?? []
        activityEvents = try container.decodeIfPresent([TripActivityEvent].self, forKey: .activityEvents)
        runState = try container.decodeIfPresent(MonitoringRunState.self, forKey: .runState) ?? .active
        lastMovementDetectedAt = try container.decodeIfPresent(Date.self, forKey: .lastMovementDetectedAt)
        lastMovementLatitude = try container.decodeIfPresent(Double.self, forKey: .lastMovementLatitude)
        lastMovementLongitude = try container.decodeIfPresent(Double.self, forKey: .lastMovementLongitude)
        latestDetectedActivity = try container.decodeIfPresent(
            DetectedJourneyActivity.self,
            forKey: .latestDetectedActivity
        ) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startLatitude, forKey: .startLatitude)
        try container.encode(startLongitude, forKey: .startLongitude)
        try container.encode(destinationLatitude, forKey: .destinationLatitude)
        try container.encode(destinationLongitude, forKey: .destinationLongitude)
        try container.encode(leadTimeMinutes, forKey: .leadTimeMinutes)
        try container.encode(selectedJourneyMode, forKey: .selectedJourneyMode)
        try container.encodeIfPresent(journeyPlanItemID, forKey: .journeyPlanItemID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(routePoints, forKey: .routePoints)
        try container.encodeIfPresent(activityEvents, forKey: .activityEvents)
        try container.encode(runState, forKey: .runState)
        try container.encodeIfPresent(lastMovementDetectedAt, forKey: .lastMovementDetectedAt)
        try container.encodeIfPresent(lastMovementLatitude, forKey: .lastMovementLatitude)
        try container.encodeIfPresent(lastMovementLongitude, forKey: .lastMovementLongitude)
        try container.encode(latestDetectedActivity, forKey: .latestDetectedActivity)
    }
}

private struct PersistedHistorySession: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let startLatitude: Double
    let startLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let pointsCount: Int
    let gpxFileName: String
    let gpxFilePath: String
    let completionStatus: JourneyCompletionStatus
    let selectedJourneyMode: JourneyMode
    let finalDetectedActivity: DetectedJourneyActivity
    let activityEvents: [TripActivityEvent]?

    init(_ session: TripHistorySession) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        startLatitude = session.startLatitude
        startLongitude = session.startLongitude
        destinationLatitude = session.destinationLatitude
        destinationLongitude = session.destinationLongitude
        pointsCount = session.pointsCount
        gpxFileName = session.gpxFileName
        gpxFilePath = session.gpxFilePath
        completionStatus = session.completionStatus
        selectedJourneyMode = session.selectedJourneyMode
        finalDetectedActivity = session.finalDetectedActivity
        activityEvents = session.activityEvents
    }

    var domain: TripHistorySession {
        TripHistorySession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude,
            pointsCount: pointsCount,
            gpxFileName: gpxFileName,
            gpxFilePath: gpxFilePath,
            completionStatus: completionStatus,
            selectedJourneyMode: selectedJourneyMode,
            finalDetectedActivity: finalDetectedActivity,
            activityEvents: activityEvents ?? []
        )
    }
}

struct TravelAssistWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var etaMinutes: Int
        var statusText: String
        var progress: Double
        var distanceText: String
        var modeSymbolName: String
        var modeTitle: String
    }

    var name: String
}
