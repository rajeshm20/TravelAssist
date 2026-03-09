import CoreLocation
import Foundation

final class CurrentLocationProviderAdapter: CurrentLocationProvider {
    private let locationService: LocationService

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    var currentCoordinate: CLLocationCoordinate2D? {
        locationService.currentLocation?.coordinate
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationService.authorizationStatus
    }

    func requestAccessIfNeeded() {
        locationService.requestPermissionsIfNeeded()
    }

    func startSampling() {
        locationService.startStandardUpdates()
    }
}
