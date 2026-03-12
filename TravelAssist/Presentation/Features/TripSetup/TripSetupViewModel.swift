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
    private let updateJourneyModeUseCase: UpdateJourneyModeUseCase
    private let recordTripUserActionUseCase: RecordTripUserActionUseCase
    private let triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    private let defaults = UserDefaults.standard
    private let persistedSetupKey = "tripsetup.persisted.selection"

    init(
        buildTripSessionUseCase: BuildTripSessionUseCase,
        prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase,
        startUseCase: StartTripMonitoringUseCase,
        updateJourneyModeUseCase: UpdateJourneyModeUseCase,
        recordTripUserActionUseCase: RecordTripUserActionUseCase,
        triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    ) {
        self.buildTripSessionUseCase = buildTripSessionUseCase
        self.prepareCurrentLocationUseCase = prepareCurrentLocationUseCase
        self.startUseCase = startUseCase
        self.updateJourneyModeUseCase = updateJourneyModeUseCase
        self.recordTripUserActionUseCase = recordTripUserActionUseCase
        self.triggerTestFakeCallUseCase = triggerTestFakeCallUseCase
    }

    func onAppear() {
        restorePersistedSetupIfNeeded()
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
            persistCurrentSetup()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyDestinationFromAppleMaps(name: String, coordinate: CLLocationCoordinate2D) {
        selectedDestinationName = name
        destinationLatitudeText = String(format: "%.7f", coordinate.latitude)
        destinationLongitudeText = String(format: "%.7f", coordinate.longitude)
        persistCurrentSetup()
        recordTripUserActionUseCase.execute(
            status: String(
                format: "Destination updated to %@ (%.5f, %.5f)",
                name,
                coordinate.latitude,
                coordinate.longitude
            )
        )
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
        persistCurrentSetup()
        recordTripUserActionUseCase.execute(
            status: "Lead time changed to \(leadTimeFormatted)"
        )
    }

    func applySelectedJourneyModeToActiveSession() {
        persistCurrentSetup()
        updateJourneyModeUseCase.execute(mode: selectedJourneyMode)
        recordTripUserActionUseCase.execute(
            status: "Journey mode changed by user to \(selectedJourneyMode.title)"
        )
    }

    func triggerTestFakeCall() {
        triggerTestFakeCallUseCase.execute()
    }

    private func resolvedLeadTimeMinutes() -> Int {
        (selectedLeadHours * 60) + selectedLeadMinutes
    }

    private func persistCurrentSetup() {
        let payload = PersistedTripSetupState(
            destinationLatitudeText: destinationLatitudeText,
            destinationLongitudeText: destinationLongitudeText,
            selectedDestinationName: selectedDestinationName,
            selectedJourneyModeRaw: selectedJourneyMode.rawValue,
            selectedLeadHours: selectedLeadHours,
            selectedLeadMinutes: selectedLeadMinutes
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: persistedSetupKey)
    }

    private func restorePersistedSetupIfNeeded() {
        guard let data = defaults.data(forKey: persistedSetupKey),
              let payload = try? JSONDecoder().decode(PersistedTripSetupState.self, from: data) else {
            return
        }

        destinationLatitudeText = payload.destinationLatitudeText
        destinationLongitudeText = payload.destinationLongitudeText
        selectedDestinationName = payload.selectedDestinationName
        selectedJourneyMode = JourneyMode(rawValue: payload.selectedJourneyModeRaw) ?? .car
        selectedLeadHours = min(max(payload.selectedLeadHours, 0), 23)
        selectedLeadMinutes = min(max(payload.selectedLeadMinutes, 0), 59)
    }
}

private struct PersistedTripSetupState: Codable {
    let destinationLatitudeText: String
    let destinationLongitudeText: String
    let selectedDestinationName: String?
    let selectedJourneyModeRaw: String
    let selectedLeadHours: Int
    let selectedLeadMinutes: Int
}
