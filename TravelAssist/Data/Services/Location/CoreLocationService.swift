import Combine
import CoreLocation
import Foundation

final class CoreLocationService: NSObject, LocationService {
    private let manager = CLLocationManager()
    private var lastKnownLocation: CLLocation?
    private var lastPublishedLocation: CLLocation?
    private var wantsStandardUpdates = false
    private var wantsSignificantUpdates = false
    private var wantsOneTimeLocation = false
    private var isStandardUpdatesActive = false
    private var isSignificantUpdatesActive = false

    private let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 80
    private let maximumLocationAgeSeconds: TimeInterval = 15
    private let minimumJitterDistanceMeters: CLLocationDistance = 6

    private let authorizationSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)
    private let locationSubject = PassthroughSubject<CLLocation, Never>()

    var currentLocation: CLLocation? {
        lastKnownLocation ?? manager.location
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject.eraseToAnyPublisher()
    }

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        if Self.supportsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = true
        }
        authorizationSubject.send(manager.authorizationStatus)
    }

    func requestPermissionsIfNeeded() {
        let status = manager.authorizationStatus
        authorizationSubject.send(status)

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startStandardUpdates() {
        wantsStandardUpdates = true
        applyPendingRequestsIfAuthorized()
    }

    func stopStandardUpdates() {
        wantsStandardUpdates = false
        guard isStandardUpdatesActive else { return }
        manager.stopUpdatingLocation()
        isStandardUpdatesActive = false
    }

    func requestOneTimeLocation() {
        wantsOneTimeLocation = true
        applyPendingRequestsIfAuthorized()
    }

    func startSignificantUpdates() {
        wantsSignificantUpdates = true
        applyPendingRequestsIfAuthorized()
    }

    func stopUpdates() {
        wantsStandardUpdates = false
        wantsSignificantUpdates = false
        wantsOneTimeLocation = false

        if isStandardUpdatesActive {
            manager.stopUpdatingLocation()
            isStandardUpdatesActive = false
        }

        if isSignificantUpdatesActive {
            manager.stopMonitoringSignificantLocationChanges()
            isSignificantUpdatesActive = false
        }

        stopMonitoringDestination()
    }

    func startMonitoringDestination(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) {
        stopMonitoringDestination()

        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: AppConstants.destinationRegionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func stopMonitoringDestination() {
        manager.monitoredRegions
            .filter { $0.identifier == AppConstants.destinationRegionIdentifier }
            .forEach { manager.stopMonitoring(for: $0) }
    }

    private static var supportsBackgroundLocationUpdates: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    private func applyPendingRequestsIfAuthorized() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            requestPermissionsIfNeeded()
            return
        }

        if wantsStandardUpdates && !isStandardUpdatesActive {
            manager.startUpdatingLocation()
            isStandardUpdatesActive = true
        } else if !wantsStandardUpdates && isStandardUpdatesActive {
            manager.stopUpdatingLocation()
            isStandardUpdatesActive = false
        }

        if wantsSignificantUpdates && !isSignificantUpdatesActive {
            manager.startMonitoringSignificantLocationChanges()
            isSignificantUpdatesActive = true
        } else if !wantsSignificantUpdates && isSignificantUpdatesActive {
            manager.stopMonitoringSignificantLocationChanges()
            isSignificantUpdatesActive = false
        }

        if wantsOneTimeLocation {
            wantsOneTimeLocation = false
            manager.requestLocation()
        }
    }

    private func publishIfMeaningful(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maximumHorizontalAccuracyMeters else {
            return
        }
        guard abs(location.timestamp.timeIntervalSinceNow) <= maximumLocationAgeSeconds else {
            return
        }

        if let previous = lastPublishedLocation {
            let movedMeters = location.distance(from: previous)
            let speed = max(location.speed, 0)
            let jitterThreshold = max(
                minimumJitterDistanceMeters,
                min(25, location.horizontalAccuracy * 0.5)
            )
            if movedMeters < jitterThreshold && speed < 0.8 {
                return
            }
        }

        lastKnownLocation = location
        lastPublishedLocation = location
        locationSubject.send(location)
    }

    private func bestLocation(from locations: [CLLocation]) -> CLLocation? {
        locations
            .filter { $0.horizontalAccuracy >= 0 }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }
}

extension CoreLocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorizationSubject.send(status)

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            applyPendingRequestsIfAuthorized()
        }

        if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = bestLocation(from: locations) ?? locations.last else { return }
        publishIfMeaningful(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `requestLocation()` can fail transiently (for example while GPS is warming up).
        // Ignore and keep the last known location if available.
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }

        if let location = manager.location ?? lastKnownLocation {
            publishIfMeaningful(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == AppConstants.destinationRegionIdentifier else { return }
        if let location = manager.location ?? lastKnownLocation {
            publishIfMeaningful(location)
        }
    }
}
