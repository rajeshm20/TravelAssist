import Foundation
import WidgetKit
internal import _LocationEssentials

protocol WidgetSyncService {
    func sync(snapshot: TravelSnapshot, session: TripSession)
    func clear()
}

final class SharedDefaultsWidgetSyncService: WidgetSyncService {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()

    init(appGroupID: String) {
        defaults = UserDefaults(suiteName: appGroupID)
    }

    func sync(snapshot: TravelSnapshot, session: TripSession) {
        guard let defaults else { return }

        if let snapshotData = try? encoder.encode(TravelWidgetSnapshotDTO(snapshot: snapshot)),
           let sessionData = try? encoder.encode(TravelWidgetSessionDTO(session: session)) {
            defaults.set(snapshotData, forKey: "widget.snapshot")
            defaults.set(sessionData, forKey: "widget.session")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: "widget.snapshot")
        defaults.removeObject(forKey: "widget.session")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct TravelWidgetSnapshotDTO: Codable {
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let etaSeconds: Double
    let updatedAt: Date

    init(snapshot: TravelSnapshot) {
        latitude = snapshot.currentCoordinate.latitude
        longitude = snapshot.currentCoordinate.longitude
        distanceMeters = snapshot.distanceMeters
        etaSeconds = snapshot.etaSeconds
        updatedAt = snapshot.updatedAt
    }
}

struct TravelWidgetSessionDTO: Codable {
    let startLatitude: Double
    let startLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let leadTimeMinutes: Int
    let startedAt: Date

    init(session: TripSession) {
        startLatitude = session.startCoordinate.latitude
        startLongitude = session.startCoordinate.longitude
        destinationLatitude = session.destinationCoordinate.latitude
        destinationLongitude = session.destinationCoordinate.longitude
        leadTimeMinutes = session.leadTimeMinutes
        startedAt = session.startedAt
    }
}
