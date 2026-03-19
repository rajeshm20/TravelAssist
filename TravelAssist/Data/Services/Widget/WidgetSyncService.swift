import Foundation
import WidgetKit
internal import _LocationEssentials

protocol WidgetSyncService {
    func sync(snapshot: TravelSnapshot?, session: TripSession?)
    func syncJourneyPlan(_ items: [JourneyPlanItem])
    func clearActiveTrip()
}

final class SharedDefaultsWidgetSyncService: WidgetSyncService {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let lock = NSLock()
    private let minimumReloadIntervalSeconds: TimeInterval = 120
    private var lastSyncedSnapshot: TravelWidgetSnapshotDTO?
    private var lastSyncedSession: TravelWidgetSessionDTO?
    private var lastSyncedJourneyPlan: [TravelWidgetJourneyPlanDTO] = []
    private var lastReloadAt: Date?

    init(appGroupID: String) {
        defaults = UserDefaults(suiteName: appGroupID)
    }

    func sync(snapshot: TravelSnapshot?, session: TripSession?) {
        guard let defaults else { return }

        let snapshotDTO = snapshot.map(TravelWidgetSnapshotDTO.init)
        let sessionDTO = session.map(TravelWidgetSessionDTO.init)
        let shouldReload = shouldReloadTimelines(
            snapshot: snapshotDTO,
            session: sessionDTO,
            journeyPlan: nil
        )

        if let snapshotDTO,
           let snapshotData = try? encoder.encode(snapshotDTO) {
            defaults.set(snapshotData, forKey: "widget.snapshot")
        } else {
            defaults.removeObject(forKey: "widget.snapshot")
        }

        if let sessionDTO,
           let sessionData = try? encoder.encode(sessionDTO) {
            defaults.set(sessionData, forKey: "widget.session")
        } else {
            defaults.removeObject(forKey: "widget.session")
        }

        if shouldReload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func syncJourneyPlan(_ items: [JourneyPlanItem]) {
        guard let defaults else { return }

        let dtoItems = items.map(TravelWidgetJourneyPlanDTO.init)
        let shouldReload = shouldReloadTimelines(
            snapshot: nil,
            session: nil,
            journeyPlan: dtoItems
        )

        if dtoItems.isEmpty {
            defaults.removeObject(forKey: "widget.plan")
        } else if let data = try? encoder.encode(dtoItems) {
            defaults.set(data, forKey: "widget.plan")
        }

        if shouldReload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func clearActiveTrip() {
        guard let defaults else { return }
        defaults.removeObject(forKey: "widget.snapshot")
        defaults.removeObject(forKey: "widget.session")
        lock.lock()
        lastSyncedSnapshot = nil
        lastSyncedSession = nil
        if lastSyncedJourneyPlan.isEmpty {
            lastReloadAt = nil
        }
        lock.unlock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func shouldReloadTimelines(
        snapshot: TravelWidgetSnapshotDTO?,
        session: TravelWidgetSessionDTO?,
        journeyPlan: [TravelWidgetJourneyPlanDTO]?
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let resolvedSnapshot = snapshot ?? lastSyncedSnapshot
        let resolvedSession = session ?? lastSyncedSession
        let resolvedJourneyPlan = journeyPlan ?? lastSyncedJourneyPlan

        defer {
            lastSyncedSnapshot = resolvedSnapshot
            lastSyncedSession = resolvedSession
            lastSyncedJourneyPlan = resolvedJourneyPlan
        }

        if lastSyncedSnapshot == nil,
           lastSyncedSession == nil,
           lastSyncedJourneyPlan.isEmpty {
            lastReloadAt = now
            return true
        }

        let sessionChanged = lastSyncedSession != resolvedSession
        let journeyPlanChanged = lastSyncedJourneyPlan != resolvedJourneyPlan
        let stateChanged = lastSyncedSnapshot?.monitoringStateRaw != resolvedSnapshot?.monitoringStateRaw
        let activityChanged = lastSyncedSnapshot?.detectedActivityRaw != resolvedSnapshot?.detectedActivityRaw
        let distanceChanged = abs((lastSyncedSnapshot?.distanceMeters ?? 0) - (resolvedSnapshot?.distanceMeters ?? 0)) >= 50
        let etaChanged = abs((lastSyncedSnapshot?.etaSeconds ?? 0) - (resolvedSnapshot?.etaSeconds ?? 0)) >= 60
        let staleReload = lastReloadAt.map { now.timeIntervalSince($0) >= minimumReloadIntervalSeconds } ?? true

        let shouldReload = sessionChanged || journeyPlanChanged || stateChanged || activityChanged || distanceChanged || etaChanged || staleReload
        if shouldReload {
            lastReloadAt = now
        }
        return shouldReload
    }
}

struct TravelWidgetSnapshotDTO: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let etaSeconds: Double
    let detectedActivityRaw: String?
    let monitoringStateRaw: String?
    let updatedAt: Date

    init(snapshot: TravelSnapshot) {
        latitude = snapshot.currentCoordinate.latitude
        longitude = snapshot.currentCoordinate.longitude
        distanceMeters = snapshot.distanceMeters
        etaSeconds = snapshot.etaSeconds
        detectedActivityRaw = snapshot.detectedActivity.rawValue
        monitoringStateRaw = snapshot.monitoringState.rawValue
        updatedAt = snapshot.updatedAt
    }
}

struct TravelWidgetSessionDTO: Codable, Equatable {
    let startLatitude: Double
    let startLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let leadTimeMinutes: Int
    let selectedJourneyModeRaw: String?
    let journeyPlanItemID: UUID?
    let startedAt: Date

    init(session: TripSession) {
        startLatitude = session.startCoordinate.latitude
        startLongitude = session.startCoordinate.longitude
        destinationLatitude = session.destinationCoordinate.latitude
        destinationLongitude = session.destinationCoordinate.longitude
        leadTimeMinutes = session.leadTimeMinutes
        selectedJourneyModeRaw = session.selectedJourneyMode.rawValue
        journeyPlanItemID = session.journeyPlanItemID
        startedAt = session.startedAt
    }
}

struct TravelWidgetJourneyPlanDTO: Codable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
    let plannedStartAt: Date
    let approximateEndAt: Date
    let estimatedTravelDurationSeconds: TimeInterval
    let selectedJourneyModeRaw: String?
    let leadTimeMinutes: Int
    let statusRaw: String?

    init(item: JourneyPlanItem) {
        id = item.id
        title = item.title
        subtitle = item.subtitle
        latitude = item.latitude
        longitude = item.longitude
        plannedStartAt = item.plannedStartAt
        approximateEndAt = item.approximateEndAt
        estimatedTravelDurationSeconds = item.estimatedTravelDurationSeconds
        selectedJourneyModeRaw = item.selectedJourneyMode.rawValue
        leadTimeMinutes = item.leadTimeMinutes
        statusRaw = item.status.rawValue
    }
}
