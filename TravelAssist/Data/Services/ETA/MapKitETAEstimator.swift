import CoreLocation
import Foundation
import MapKit

final class MapKitETAEstimator: ETAEstimator {
    private let minimumReliableSpeedMetersPerSecond: CLLocationSpeed = 1.0
    private let routeRefreshMinimumIntervalSeconds: TimeInterval = 180
    private let routeRefreshMinimumDistanceMeters: CLLocationDistance = 125
    private let cacheLock = NSLock()
    private var cachedRoute: CachedRouteEstimate?

    func estimateETA(
        from currentLocation: CLLocation,
        to destination: CLLocationCoordinate2D,
        mode: JourneyMode
    ) async -> ETAEstimate {
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let fallbackDistance = max(0, currentLocation.distance(from: destinationLocation))
        let fallbackEstimate = ETAEstimate(
            distanceMeters: fallbackDistance,
            etaSeconds: fallbackDistance / resolvedSpeed(from: currentLocation, mode: mode)
        )

        if let cachedEstimate = cachedEstimateIfUsable(
            from: currentLocation,
            to: destination,
            mode: mode,
            fallbackDistance: fallbackDistance
        ) {
            return cachedEstimate
        }

        #if targetEnvironment(simulator)
        // Routing responses can be noisy in Simulator, so use deterministic movement-based values.
        return fallbackEstimate
        #else

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType(for: mode)
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = preferredRoute(from: response.routes) {
                let adjustedTime = adjustedTravelTime(route.expectedTravelTime, mode: mode)
                storeCachedRoute(
                    currentLocation: currentLocation,
                    destination: destination,
                    mode: mode,
                    fallbackDistance: fallbackDistance,
                    adjustedTime: adjustedTime
                )
                // Keep distance based on the user's live GPS position to avoid route-distance jumps.
                return ETAEstimate(
                    distanceMeters: fallbackDistance,
                    etaSeconds: max(0, adjustedTime)
                )
            }
        } catch {
            // Falls back to speed-based ETA when routing is not available.
        }

        return fallbackEstimate
        #endif
    }

    private func preferredRoute(from routes: [MKRoute]) -> MKRoute? {
        guard !routes.isEmpty else { return nil }
        guard let fastest = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else { return routes.first }
        let maxAllowedTime = fastest.expectedTravelTime * 1.25

        let candidates = routes.filter { $0.expectedTravelTime <= maxAllowedTime }
        if candidates.isEmpty {
            return fastest
        }

        return candidates.min { lhs, rhs in
            if lhs.distance == rhs.distance {
                return lhs.expectedTravelTime < rhs.expectedTravelTime
            }
            return lhs.distance < rhs.distance
        }
    }

    private func cachedEstimateIfUsable(
        from currentLocation: CLLocation,
        to destination: CLLocationCoordinate2D,
        mode: JourneyMode,
        fallbackDistance: CLLocationDistance
    ) -> ETAEstimate? {
        cacheLock.lock()
        let cachedRoute = cachedRoute
        cacheLock.unlock()

        guard let cachedRoute else { return nil }
        guard cachedRoute.mode == mode else { return nil }
        guard cachedRoute.destination.latitude == destination.latitude,
              cachedRoute.destination.longitude == destination.longitude else {
            return nil
        }

        let age = Date().timeIntervalSince(cachedRoute.updatedAt)
        let movedMeters = currentLocation.distance(from: cachedRoute.originLocation)
        guard age < routeRefreshMinimumIntervalSeconds || movedMeters < routeRefreshMinimumDistanceMeters else {
            return nil
        }

        let etaSeconds = fallbackDistance / cachedRoute.effectiveSpeedMetersPerSecond
        return ETAEstimate(distanceMeters: fallbackDistance, etaSeconds: max(0, etaSeconds))
    }

    private func storeCachedRoute(
        currentLocation: CLLocation,
        destination: CLLocationCoordinate2D,
        mode: JourneyMode,
        fallbackDistance: CLLocationDistance,
        adjustedTime: TimeInterval
    ) {
        guard adjustedTime > 0, fallbackDistance > 0 else { return }

        let effectiveSpeedMetersPerSecond = max(
            minimumReliableSpeedMetersPerSecond,
            fallbackDistance / adjustedTime
        )

        cacheLock.lock()
        cachedRoute = CachedRouteEstimate(
            originLocation: currentLocation,
            destination: destination,
            mode: mode,
            effectiveSpeedMetersPerSecond: effectiveSpeedMetersPerSecond,
            updatedAt: Date()
        )
        cacheLock.unlock()
    }

    private func resolvedSpeed(from location: CLLocation, mode: JourneyMode) -> CLLocationSpeed {
        let baseline = fallbackSpeed(for: mode)
        if location.speed.isFinite, location.speed > minimumReliableSpeedMetersPerSecond {
            // Keep mode influence even when GPS speed is available, so mode switch updates ETA.
            return max((location.speed * 0.35) + (baseline * 0.65), minimumReliableSpeedMetersPerSecond)
        }
        return baseline
    }

    private func fallbackSpeed(for mode: JourneyMode) -> CLLocationSpeed {
        switch mode {
        case .walk:
            return 1.4
        case .run:
            return 2.7
        case .cycle:
            return 5.5
        case .motorbike:
            return 13.0
        case .bus:
            return 8.5
        case .car:
            return 11.0
        }
    }

    private func transportType(for mode: JourneyMode) -> MKDirectionsTransportType {
        switch mode {
        case .walk, .run, .cycle:
            return .walking
        case .bus:
            return .transit
        case .motorbike, .car:
            return .automobile
        }
    }

    private func adjustedTravelTime(_ expectedTravelTime: TimeInterval, mode: JourneyMode) -> TimeInterval {
        let factor: Double
        switch mode {
        case .walk:
            factor = 1.0
        case .run:
            factor = 0.65
        case .cycle:
            factor = 0.45
        case .motorbike:
            factor = 0.8
        case .bus:
            factor = 1.1
        case .car:
            factor = 1.0
        }
        return expectedTravelTime * factor
    }
}

private struct CachedRouteEstimate {
    let originLocation: CLLocation
    let destination: CLLocationCoordinate2D
    let mode: JourneyMode
    let effectiveSpeedMetersPerSecond: CLLocationSpeed
    let updatedAt: Date
}
