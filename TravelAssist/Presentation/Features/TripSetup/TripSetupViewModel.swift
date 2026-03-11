import CoreLocation
import Foundation
import Combine

@MainActor
final class TripSetupViewModel: ObservableObject {
    @Published var destinationLatitudeText = ""
    @Published var destinationLongitudeText = ""
    @Published var selectedDestinationName: String?
    @Published var selectedJourneyMode: JourneyMode = .car
    @Published var selectedLeadHours = 0
    @Published var selectedLeadMinutes = 10

    @Published var errorMessage: String?

    let leadHourOptions = Array(0...23)
    let leadMinuteOptions = Array(0...59)

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
        guard leadTime > 0 else {
            errorMessage = "Lead time must be at least 00:01."
            return
        }

        let destination = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        prepareCurrentLocationUseCase.execute()

        do {
            let session = try buildTripSessionUseCase.execute(
                destination: destination,
                leadTimeMinutes: leadTime,
                selectedJourneyMode: selectedJourneyMode
            )
            startUseCase.execute(session: session)
            errorMessage = nil
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

    var leadTimeFormatted: String {
        String(format: "%02d:%02d", selectedLeadHours, selectedLeadMinutes)
    }

    var leadTimePickerDate: Date {
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = selectedLeadHours
        components.minute = selectedLeadMinutes
        return Calendar.current.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    func updateLeadTime(from date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        selectedLeadHours = min(max(components.hour ?? 0, 0), 23)
        selectedLeadMinutes = min(max(components.minute ?? 0, 0), 59)
    }

    private func resolvedLeadTimeMinutes() -> Int {
        (selectedLeadHours * 60) + selectedLeadMinutes
    }
}
