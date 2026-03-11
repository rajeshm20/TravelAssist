import CoreLocation
import Foundation

struct TravelSnapshot {
    let currentCoordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let etaSeconds: TimeInterval
    let detectedActivity: DetectedJourneyActivity
    let monitoringState: MonitoringRunState
    let updatedAt: Date

    var etaMinutes: Int {
        Int((etaSeconds / 60.0).rounded())
    }
}
