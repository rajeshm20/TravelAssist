import CoreLocation
import Foundation

enum BuildTripSessionError: LocalizedError {
    case invalidLeadTime
    case locationPermissionDenied
    case currentLocationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidLeadTime:
            return "Lead time must be greater than zero."
        case .locationPermissionDenied:
            return "Location permission denied. Enable location access in Settings."
        case .currentLocationUnavailable:
            return "Current location unavailable. Wait for GPS and try again."
        }
    }
}

protocol BuildTripSessionUseCase {
    func execute(
        destination: CLLocationCoordinate2D,
        leadTimeMinutes: Int,
        selectedJourneyMode: JourneyMode,
        startCoordinateOverride: CLLocationCoordinate2D?
    ) throws -> TripSession
}

struct BuildTripSessionUseCaseImpl: BuildTripSessionUseCase {
    private let locationProvider: CurrentLocationProvider

    init(locationProvider: CurrentLocationProvider) {
        self.locationProvider = locationProvider
    }

    func execute(
        destination: CLLocationCoordinate2D,
        leadTimeMinutes: Int,
        selectedJourneyMode: JourneyMode,
        startCoordinateOverride: CLLocationCoordinate2D? = nil
    ) throws -> TripSession {
        guard leadTimeMinutes > 0 else {
            throw BuildTripSessionError.invalidLeadTime
        }
        locationProvider.requestAccessIfNeeded()
        locationProvider.startSampling()

        let startCoordinate: CLLocationCoordinate2D
        if let startCoordinateOverride {
            startCoordinate = startCoordinateOverride
        } else if let currentCoordinate = locationProvider.currentCoordinate {
            startCoordinate = currentCoordinate
        } else {
            if locationProvider.authorizationStatus == .denied || locationProvider.authorizationStatus == .restricted {
                throw BuildTripSessionError.locationPermissionDenied
            }
            throw BuildTripSessionError.currentLocationUnavailable
        }

        return TripSession(
            startCoordinate: startCoordinate,
            destinationCoordinate: destination,
            leadTimeMinutes: leadTimeMinutes,
            selectedJourneyMode: selectedJourneyMode
        )
    }
}
