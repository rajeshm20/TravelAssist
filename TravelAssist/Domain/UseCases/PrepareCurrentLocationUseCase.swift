import Foundation

protocol PrepareCurrentLocationUseCase {
    func execute()
}

struct PrepareCurrentLocationUseCaseImpl: PrepareCurrentLocationUseCase {
    private let locationProvider: CurrentLocationProvider

    init(locationProvider: CurrentLocationProvider) {
        self.locationProvider = locationProvider
    }

    func execute() {
        locationProvider.requestAccessIfNeeded()
        locationProvider.startSampling()
    }
}

