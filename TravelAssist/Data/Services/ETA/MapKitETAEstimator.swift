import CoreLocation
import Foundation
import MapKit

final class MapKitETAEstimator: ETAEstimator {
    private let fallbackAverageSpeedMetersPerSecond: CLLocationSpeed = 9.72 // ~35 km/h
    private let minimumReliableSpeedMetersPerSecond: CLLocationSpeed = 1.0

    func estimateETA(from currentLocation: CLLocation, to destination: CLLocationCoordinate2D) async -> ETAEstimate {
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let fallbackDistance = max(0, currentLocation.distance(from: destinationLocation))
        let fallbackEstimate = ETAEstimate(
            distanceMeters: fallbackDistance,
            etaSeconds: fallbackDistance / resolvedSpeed(from: currentLocation)
        )

        #if targetEnvironment(simulator)
        // Routing responses can be noisy in Simulator, so use deterministic movement-based values.
        return fallbackEstimate
        #else

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = response.routes.first {
                // Keep distance based on the user's live GPS position to avoid route-distance jumps.
                return ETAEstimate(
                    distanceMeters: fallbackDistance,
                    etaSeconds: max(0, route.expectedTravelTime)
                )
            }
        } catch {
            // Falls back to speed-based ETA when routing is not available.
        }

        return fallbackEstimate
        #endif
    }

    private func resolvedSpeed(from location: CLLocation) -> CLLocationSpeed {
        if location.speed.isFinite, location.speed > minimumReliableSpeedMetersPerSecond {
            return location.speed
        }
        return fallbackAverageSpeedMetersPerSecond
    }
}
