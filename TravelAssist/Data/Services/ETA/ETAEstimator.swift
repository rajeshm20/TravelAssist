import CoreLocation
import Foundation

struct ETAEstimate: Equatable {
    let distanceMeters: CLLocationDistance
    let etaSeconds: TimeInterval
}

protocol ETAEstimator {
    func estimateETA(
        from currentLocation: CLLocation,
        to destination: CLLocationCoordinate2D,
        mode: JourneyMode
    ) async -> ETAEstimate
}
