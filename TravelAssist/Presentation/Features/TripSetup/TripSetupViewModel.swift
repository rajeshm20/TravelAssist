import CoreLocation
import Foundation
import Combine

@MainActor
final class TripSetupViewModel: ObservableObject {
    @Published var destinationLatitudeText = ""
    @Published var destinationLongitudeText = ""
    @Published var selectedDestinationName: String?
    @Published var selectedLeadTimeMinutes = 10
    @Published var customLeadTimeText = ""
    @Published var useCustomLeadTime = false

    @Published var isMonitoringScreenPresented = false
    @Published var errorMessage: String?

    let leadTimeOptions = [5, 10, 20, 30]

    private let buildTripSessionUseCase: BuildTripSessionUseCase
    private let prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase
    private let startUseCase: StartTripMonitoringUseCase

    init(
        buildTripSessionUseCase: BuildTripSessionUseCase,
        prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase,
        startUseCase: StartTripMonitoringUseCase
    ) {
        self.buildTripSessionUseCase = buildTripSessionUseCase
        self.prepareCurrentLocationUseCase = prepareCurrentLocationUseCase
        self.startUseCase = startUseCase
    }

    func onAppear() {
        prepareCurrentLocationUseCase.execute()
    }

    func startMonitoring() {
        guard let latitude = Double(destinationLatitudeText),
              let longitude = Double(destinationLongitudeText) else {
            errorMessage = "Enter valid destination coordinates."
            return
        }

        let leadTime = resolvedLeadTimeMinutes()
        let destination = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        prepareCurrentLocationUseCase.execute()

        do {
            let session = try buildTripSessionUseCase.execute(
                destination: destination,
                leadTimeMinutes: leadTime
            )
            startUseCase.execute(session: session)
            errorMessage = nil
            isMonitoringScreenPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyDestinationFromAppleMaps(name: String, coordinate: CLLocationCoordinate2D) {
        selectedDestinationName = name
        destinationLatitudeText = String(format: "%.7f", coordinate.latitude)
        destinationLongitudeText = String(format: "%.7f", coordinate.longitude)
        errorMessage = nil
    }

    private func resolvedLeadTimeMinutes() -> Int {
        if useCustomLeadTime {
            return Int(customLeadTimeText) ?? 0
        }
        return selectedLeadTimeMinutes
    }
}
