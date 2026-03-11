import Combine
import CoreLocation
import Foundation
import ActivityKit

final class TripMonitoringRepositoryImpl: TripMonitoringRepository {
    private enum StorageKeys {
        static let activeSession = "trip.active.session"
        static let historySessions = "trip.history.sessions"
    }

    private let locationService: LocationService
    private let etaEstimator: ETAEstimator
    private let alertService: FakeCallAlertService
    private let backgroundTaskScheduler: BackgroundTaskScheduler
    private let widgetSyncService: WidgetSyncService
    private let defaults: UserDefaults?

    private let stationaryFreezeDistanceMeters: CLLocationDistance = 12
    private let maximumStationaryJitterMeters: CLLocationDistance = 35
    private let minimumArrivalClampMeters: CLLocationDistance = 20
    private let maximumArrivalClampMeters: CLLocationDistance = 45
    private let routePointMinimumDistanceMeters: CLLocationDistance = 5
    private let routePointMinimumIntervalSeconds: TimeInterval = 10
    private let intervalCheckSeconds: TimeInterval = 60
    private let idleTimeoutSeconds: TimeInterval = 10 * 60

    private var cancellables = Set<AnyCancellable>()
    private var intervalCancellable: AnyCancellable?
    private var estimateTask: Task<Void, Never>?
    private var hasTriggeredFakeCall = false
    private var hasReachedDestination = false
    private var liveActivity: Activity<TravelAssistWidgetAttributes>?
    private var currentRoutePoints: [PersistedTrackPoint] = []

    private var runState: MonitoringRunState = .active
    private var lastMovementDetectedAt: Date?
    private var lastMovementLocation: CLLocation?
    private var latestDetectedActivity: DetectedJourneyActivity = .unknown

    private let sessionSubject = CurrentValueSubject<TripSession?, Never>(nil)
    private let snapshotSubject = CurrentValueSubject<TravelSnapshot?, Never>(nil)
    private let historySubject = CurrentValueSubject<[TripHistorySession], Never>([])

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
        self.defaults = UserDefaults(suiteName: AppConstants.appGroupID)

        bindLocationUpdates()
        bindAuthorizationUpdates()
        loadPersistedHistory()
        restoreActiveSessionIfNeeded()
    }

    func start(session: TripSession) {
        if sessionSubject.value != nil {
            let previousStatus = resolvedManualStopStatus()
            completeAndStop(status: previousStatus, finalSnapshot: snapshotSubject.value)
        }

        hasTriggeredFakeCall = false
        hasReachedDestination = false
        runState = .active
        lastMovementDetectedAt = Date()
        lastMovementLocation = locationService.currentLocation
        latestDetectedActivity = .unknown

        sessionSubject.send(session)
        snapshotSubject.send(nil)
        currentRoutePoints = [
            PersistedTrackPoint(
                latitude: session.startCoordinate.latitude,
                longitude: session.startCoordinate.longitude,
                timestamp: session.startedAt
            )
        ]
        persistActiveSession(session)

        alertService.requestPermissionsIfNeeded()
        locationService.requestPermissionsIfNeeded()
        locationService.startStandardUpdates()
        locationService.startSignificantUpdates()
        locationService.requestOneTimeLocation()
        locationService.startMonitoringDestination(
            coordinate: session.destinationCoordinate,
            radius: destinationRegionRadius(for: session.leadTimeMinutes)
        )
        startLiveActivity(for: session)
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

    private func bindLocationUpdates() {
        locationService.locationPublisher
            .sink { [weak self] location in
                self?.scheduleEstimate(for: location)
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

    private func startIntervalChecks() {
        intervalCancellable?.cancel()
        guard runState == .active else { return }

        intervalCancellable = Timer.publish(every: intervalCheckSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.sessionSubject.value != nil else { return }
                guard self.runState == .active else { return }
                self.locationService.requestOneTimeLocation()
                if let location = self.locationService.currentLocation {
                    self.scheduleEstimate(for: location)
                }
            }
    }

    private func stopIntervalChecks() {
        intervalCancellable?.cancel()
        intervalCancellable = nil
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

        if runState == .atRest, !movedMeaningfully {
            publishRestSnapshot(session: session, location: location)
            return
        }

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
        persistActiveSession(session)

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

        if hasReachedDestination {
            completeAndStop(status: .destinationReached, finalSnapshot: snapshot)
        }
    }

    private func detectJourneyActivity(at location: CLLocation, previous: CLLocation?) -> DetectedJourneyActivity {
        var speed = location.speed
        if !speed.isFinite || speed < 0 {
            speed = 0
        }

        if let previous {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0 {
                let verticalSpeed = abs(location.altitude - previous.altitude) / dt
                if verticalSpeed >= 0.35 && speed < 2.8 {
                    return .climbing
                }

                if speed <= 0.1 {
                    speed = location.distance(from: previous) / dt
                }
            }
        }

        if speed < 0.7 {
            return .stationary
        }
        if speed < 2.2 {
            return .walking
        }
        if speed < 4.8 {
            return .running
        }
        return .unknown
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
        publishRestSnapshot(session: session, location: latestLocation)
        persistActiveSession(session)
    }

    private func resumeActiveMonitoring(session: TripSession, from location: CLLocation) {
        guard runState != .active else { return }

        runState = .active
        locationService.startStandardUpdates()
        locationService.requestOneTimeLocation()
        startIntervalChecks()

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
            finalDetectedActivity: latestDetectedActivity
        )
        appendToHistory(historySession)

        clearRuntimeState()
        clearPersistedActiveSession()
        widgetSyncService.clear()

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

        alertService.cancelPendingFakeCall()
        locationService.stopUpdates()

        currentRoutePoints.removeAll(keepingCapacity: false)
        lastMovementDetectedAt = nil
        lastMovementLocation = nil
        latestDetectedActivity = .unknown
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
        if snapshot.monitoringState == .atRest {
            return "At rest"
        }
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
            startedAt: session.startedAt,
            routePoints: currentRoutePoints,
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
            startedAt: persisted.startedAt
        )

        currentRoutePoints = persisted.routePoints
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

        return TravelSnapshot(
            currentCoordinate: CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude),
            distanceMeters: dto.distanceMeters,
            etaSeconds: dto.etaSeconds,
            detectedActivity: .unknown,
            monitoringState: runState,
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

    private func persistHistory(_ sessions: [TripHistorySession]) {
        guard let defaults else { return }
        let persisted = sessions.map(PersistedHistorySession.init)
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: StorageKeys.historySessions)
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

        guard let baseDirectory = try? gpxHistoryDirectory() else {
            return (fileName, "")
        }

        let fileURL = baseDirectory.appendingPathComponent(fileName)
        let gpxString = buildGPX(session: session, endedAt: endedAt, points: points)

        do {
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            return (fileName, fileURL.path)
        } catch {
            return (fileName, "")
        }
    }

    private func gpxHistoryDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = documents.appendingPathComponent("TripHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
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
    let startedAt: Date
    let routePoints: [PersistedTrackPoint]
    let runState: MonitoringRunState
    let lastMovementDetectedAt: Date?
    let lastMovementLatitude: Double?
    let lastMovementLongitude: Double?
    let latestDetectedActivity: DetectedJourneyActivity
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
            finalDetectedActivity: finalDetectedActivity
        )
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
