#if DEBUG
import Combine
import CoreLocation
import Foundation
import MapKit

final class SimulatedLocationService: LocationService {
    private let authorizationSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.authorizedAlways)
    private let locationSubject = PassthroughSubject<CLLocation, Never>()

    private let workQueue = DispatchQueue(label: "travelassist.location.simulated", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    private var lastLocation: CLLocation?
    private var destination: CLLocationCoordinate2D?
    private var wantsStandardUpdates = false

    private let speedMetersPerSecond: CLLocationSpeed
    private let updateIntervalSeconds: TimeInterval

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeProgressMeters: CLLocationDistance = 0
    private var routeTotalMeters: CLLocationDistance = 0
    private var routeSegmentLengths: [CLLocationDistance] = []

    init(
        initialCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        speedMetersPerSecond: CLLocationSpeed = 15,
        updateIntervalSeconds: TimeInterval = 1
    ) {
        self.speedMetersPerSecond = max(speedMetersPerSecond, 1)
        self.updateIntervalSeconds = max(updateIntervalSeconds, 0.25)
        self.lastLocation = CLLocation(
            coordinate: initialCoordinate,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: 0,
            speed: 0,
            timestamp: Date()
        )
    }

    var currentLocation: CLLocation? { lastLocation }

    var authorizationStatus: CLAuthorizationStatus { authorizationSubject.value }

    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject.eraseToAnyPublisher()
    }

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    func requestPermissionsIfNeeded() {
        // No-op in debug simulator. Always authorized.
        authorizationSubject.send(.authorizedAlways)
    }

    func requestOneTimeLocation() {
        guard let lastLocation else { return }
        publish(lastLocation)
    }

    func startStandardUpdates() {
        wantsStandardUpdates = true
        ensureTimer()
        if let destination {
            buildOrRebuildRoute(to: destination)
        }
    }

    func stopStandardUpdates() {
        wantsStandardUpdates = false
        stopTimerIfIdle()
    }

    func startSignificantUpdates() {
        // No-op. Standard updates drive everything.
    }

    func stopUpdates() {
        wantsStandardUpdates = false
        stopTimer()
        stopMonitoringDestination()
    }

    func startMonitoringDestination(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) {
        destination = coordinate
        if wantsStandardUpdates {
            buildOrRebuildRoute(to: coordinate)
        }
    }

    func stopMonitoringDestination() {
        destination = nil
        routeCoordinates = []
        routeSegmentLengths = []
        routeProgressMeters = 0
        routeTotalMeters = 0
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now(), repeating: updateIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerIfIdle() {
        guard !wantsStandardUpdates else { return }
        stopTimer()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard wantsStandardUpdates else { return }
        guard let lastLocation else { return }

        guard let destination else {
            // Stationary, but still emit a heartbeat location while "updates" are active.
            publish(lastLocation)
            return
        }

        if routeCoordinates.count >= 2, routeTotalMeters > 1 {
            advanceAlongRoute(from: lastLocation, destination: destination)
        } else {
            advanceStraightLine(from: lastLocation, destination: destination)
        }
    }

    private func buildOrRebuildRoute(to destination: CLLocationCoordinate2D) {
        guard let start = lastLocation?.coordinate else { return }
        routeCoordinates = []
        routeSegmentLengths = []
        routeProgressMeters = 0
        routeTotalMeters = 0

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.requestsAlternateRoutes = false
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, _ in
            guard let self else { return }
            guard let polyline = response?.routes.first?.polyline else {
                self.workQueue.async {
                    self.routeCoordinates = []
                    self.routeSegmentLengths = []
                    self.routeProgressMeters = 0
                    self.routeTotalMeters = 0
                }
                return
            }

            let coords = polylineCoordinates(polyline)
            self.workQueue.async {
                self.setRouteCoordinates(coords)
            }
        }
    }

    private func setRouteCoordinates(_ coords: [CLLocationCoordinate2D]) {
        guard coords.count >= 2 else {
            routeCoordinates = []
            routeSegmentLengths = []
            routeProgressMeters = 0
            routeTotalMeters = 0
            return
        }

        routeCoordinates = coords
        routeSegmentLengths = []
        routeSegmentLengths.reserveCapacity(coords.count - 1)

        var total: CLLocationDistance = 0
        for idx in 0..<(coords.count - 1) {
            let a = MKMapPoint(coords[idx])
            let b = MKMapPoint(coords[idx + 1])
            let segment = a.distance(to: b)
            routeSegmentLengths.append(segment)
            total += segment
        }
        routeTotalMeters = max(total, 1)
        routeProgressMeters = 0
    }

    private func advanceAlongRoute(from current: CLLocation, destination: CLLocationCoordinate2D) {
        let remaining = max(routeTotalMeters - routeProgressMeters, 0)
        if remaining <= 1 {
            publish(makeLocation(at: destination, from: current, speed: 0))
            return
        }

        routeProgressMeters = min(routeProgressMeters + (speedMetersPerSecond * updateIntervalSeconds), routeTotalMeters)
        let coordinate = coordinateAtDistance(routeProgressMeters)
        publish(makeLocation(at: coordinate, from: current, speed: speedMetersPerSecond))
    }

    private func coordinateAtDistance(_ distance: CLLocationDistance) -> CLLocationCoordinate2D {
        guard routeCoordinates.count >= 2 else {
            return lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        var remaining = max(distance, 0)
        for idx in 0..<(routeCoordinates.count - 1) {
            let segment = routeSegmentLengths[idx]
            if remaining <= segment || idx == routeCoordinates.count - 2 {
                let t = segment <= 0 ? 1 : (remaining / segment)
                return interpolate(routeCoordinates[idx], routeCoordinates[idx + 1], t: t)
            }
            remaining -= segment
        }
        return routeCoordinates.last ?? routeCoordinates[0]
    }

    private func advanceStraightLine(from current: CLLocation, destination: CLLocationCoordinate2D) {
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let remainingMeters = current.distance(from: destLocation)
        if remainingMeters <= 1 {
            publish(makeLocation(at: destination, from: current, speed: 0))
            return
        }

        let stepMeters = speedMetersPerSecond * updateIntervalSeconds
        let t = min(max(stepMeters / max(remainingMeters, 1), 0), 1)
        let next = interpolate(current.coordinate, destination, t: t)
        publish(makeLocation(at: next, from: current, speed: speedMetersPerSecond))
    }

    private func makeLocation(
        at coordinate: CLLocationCoordinate2D,
        from previous: CLLocation,
        speed: CLLocationSpeed
    ) -> CLLocation {
        let course = bearingDegrees(from: previous.coordinate, to: coordinate)
        return CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 10,
            course: course,
            speed: speed,
            timestamp: Date()
        )
    }

    private func publish(_ location: CLLocation) {
        lastLocation = location
        locationSubject.send(location)
    }
}

private func polylineCoordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
    var coords = Array(repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
    return coords
}

private func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
    let clamped = min(max(t, 0), 1)
    return CLLocationCoordinate2D(
        latitude: a.latitude + (b.latitude - a.latitude) * clamped,
        longitude: a.longitude + (b.longitude - a.longitude) * clamped
    )
}

private func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
    let lat1 = from.latitude * .pi / 180
    let lon1 = from.longitude * .pi / 180
    let lat2 = to.latitude * .pi / 180
    let lon2 = to.longitude * .pi / 180

    let dLon = lon2 - lon1
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let radians = atan2(y, x)
    let degrees = radians * 180 / .pi
    let normalized = (degrees + 360).truncatingRemainder(dividingBy: 360)
    return normalized
}
#endif

