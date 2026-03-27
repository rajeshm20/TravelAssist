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
    @Published var plannedStartDate = Date()

    @Published var errorMessage: String?

    let leadHourOptions = Array(0...23)
    let leadMinuteOptions = Array(0...59)

    private let buildTripSessionUseCase: BuildTripSessionUseCase
    private let prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase
    private let startUseCase: StartTripMonitoringUseCase
    private let updateJourneyModeUseCase: UpdateJourneyModeUseCase
    private let addJourneyPlanItemUseCase: AddJourneyPlanItemUseCase
    private let replaceJourneyPlanItemsUseCase: ReplaceJourneyPlanItemsUseCase
    private let recordTripUserActionUseCase: RecordTripUserActionUseCase
    private let triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    private let defaults = UserDefaults.standard
    private let persistedSetupKey = "tripsetup.persisted.selection"
    private let lastAutoPreviewJourneyPlanDayKey = "journeyplan.autopreview.day"

    init(
        buildTripSessionUseCase: BuildTripSessionUseCase,
        prepareCurrentLocationUseCase: PrepareCurrentLocationUseCase,
        startUseCase: StartTripMonitoringUseCase,
        updateJourneyModeUseCase: UpdateJourneyModeUseCase,
        addJourneyPlanItemUseCase: AddJourneyPlanItemUseCase,
        replaceJourneyPlanItemsUseCase: ReplaceJourneyPlanItemsUseCase,
        recordTripUserActionUseCase: RecordTripUserActionUseCase,
        triggerTestFakeCallUseCase: TriggerTestFakeCallUseCase
    ) {
        self.buildTripSessionUseCase = buildTripSessionUseCase
        self.prepareCurrentLocationUseCase = prepareCurrentLocationUseCase
        self.startUseCase = startUseCase
        self.updateJourneyModeUseCase = updateJourneyModeUseCase
        self.addJourneyPlanItemUseCase = addJourneyPlanItemUseCase
        self.replaceJourneyPlanItemsUseCase = replaceJourneyPlanItemsUseCase
        self.recordTripUserActionUseCase = recordTripUserActionUseCase
        self.triggerTestFakeCallUseCase = triggerTestFakeCallUseCase
    }

    func onAppear() {
        restorePersistedSetupIfNeeded()
        prepareCurrentLocationUseCase.execute()
    }

    func startMonitoring(using journeyPlanItems: [JourneyPlanItem] = []) {
        let selectedPlanItem = resolvedPlanItemForStart(from: journeyPlanItems)

        let destination: CLLocationCoordinate2D
        let leadTime: Int
        let journeyMode: JourneyMode
        let startCoordinateOverride: CLLocationCoordinate2D?

        if let latitude = Double(destinationLatitudeText),
           let longitude = Double(destinationLongitudeText) {
            destination = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            leadTime = resolvedLeadTimeMinutes()
            journeyMode = selectedJourneyMode
            startCoordinateOverride = nil
        } else if let selectedPlanItem {
            applyJourneyPlanSelection(selectedPlanItem)
            destination = CLLocationCoordinate2D(
                latitude: selectedPlanItem.latitude,
                longitude: selectedPlanItem.longitude
            )
            leadTime = selectedPlanItem.leadTimeMinutes
            journeyMode = selectedPlanItem.selectedJourneyMode
            startCoordinateOverride = plannedStartCoordinate(for: selectedPlanItem)
        } else {
            errorMessage = "Choose a destination or add a trip for today to start."
            return
        }

        guard leadTime > 0 else {
            errorMessage = "Lead time must be at least 00:01."
            return
        }

        prepareCurrentLocationUseCase.execute()

        do {
            let builtSession = try buildTripSessionUseCase.execute(
                destination: destination,
                leadTimeMinutes: leadTime,
                selectedJourneyMode: journeyMode,
                startCoordinateOverride: startCoordinateOverride
            )
            let session = TripSession(
                id: builtSession.id,
                startCoordinate: builtSession.startCoordinate,
                destinationCoordinate: builtSession.destinationCoordinate,
                leadTimeMinutes: builtSession.leadTimeMinutes,
                selectedJourneyMode: builtSession.selectedJourneyMode,
                journeyPlanItemID: selectedPlanItem?.id,
                startedAt: builtSession.startedAt
            )
            startUseCase.execute(session: session)
            persistCurrentSetup()
            errorMessage = nil
            if let selectedPlanItem {
                recordTripUserActionUseCase.execute(
                    status: "Started planned trip to \(selectedPlanItem.title)"
                )
            }
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

    var plannedStartFormatted: String {
        Self.plannedStartFormatter.string(from: plannedStartDate)
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

    func updatePlannedStart(from date: Date) {
        plannedStartDate = date
        persistCurrentSetup()
        recordTripUserActionUseCase.execute(
            status: "Planned start changed to \(plannedStartFormatted)"
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

    func recordShareEvent(name: String, details: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let payload: String
        if let details {
            let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            payload = trimmedDetails.isEmpty ? trimmedName : "\(trimmedName) | \(trimmedDetails)"
        } else {
            payload = trimmedName
        }

        recordTripUserActionUseCase.execute(status: payload)
    }

    func changeActiveMonitoringDestination(name: String, coordinate: CLLocationCoordinate2D) {
        applyDestinationFromAppleMaps(name: name, coordinate: coordinate)
        prepareCurrentLocationUseCase.execute()

        do {
            let session = try buildTripSessionUseCase.execute(
                destination: coordinate,
                leadTimeMinutes: resolvedLeadTimeMinutes(),
                selectedJourneyMode: selectedJourneyMode,
                startCoordinateOverride: nil
            )
            startUseCase.execute(session: session)
            persistCurrentSetup()
            errorMessage = nil
            recordTripUserActionUseCase.execute(
                status: "Active monitoring changed to \(name)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addDestinationToJourneyPlan(
        name: String,
        subtitle: String? = nil,
        coordinate: CLLocationCoordinate2D,
        estimatedTravelDurationSeconds: TimeInterval? = nil
    ) {
        let item = JourneyPlanItem(
            title: name,
            subtitle: subtitle,
            startLatitude: nil,
            startLongitude: nil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            userPlannedStartAt: plannedStartDate,
            plannedStartAt: plannedStartDate,
            estimatedTravelDurationSeconds: resolvedEstimatedTravelDuration(estimatedTravelDurationSeconds),
            selectedJourneyMode: selectedJourneyMode,
            leadTimeMinutes: resolvedLeadTimeMinutes()
        )

        addJourneyPlanItemUseCase.execute(item: item)
        persistCurrentSetup()
        errorMessage = nil
        recordTripUserActionUseCase.execute(
            status: "Destination added to journey plan: \(name)"
        )
    }

    func saveJourneyPlanItem(
        existingItems: [JourneyPlanItem],
        editing itemToEdit: JourneyPlanItem?,
        title: String,
        subtitle: String?,
        coordinate: CLLocationCoordinate2D,
        plannedStartAt: Date,
        estimatedTravelDurationSeconds: TimeInterval,
        selectedJourneyMode: JourneyMode,
        leadTimeMinutes: Int
    ) {
        let resolvedDuration = resolvedEstimatedTravelDuration(
            estimatedTravelDurationSeconds,
            minimumLeadTimeMinutes: leadTimeMinutes
        )
        let replacement = JourneyPlanItem(
            id: itemToEdit?.id ?? UUID(),
            title: title,
            subtitle: subtitle,
            startLatitude: itemToEdit?.startLatitude,
            startLongitude: itemToEdit?.startLongitude,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            userPlannedStartAt: plannedStartAt,
            plannedStartAt: plannedStartAt,
            estimatedTravelDurationSeconds: resolvedDuration,
            selectedJourneyMode: selectedJourneyMode,
            leadTimeMinutes: leadTimeMinutes,
            status: itemToEdit?.status ?? .started,
            createdAt: itemToEdit?.createdAt ?? .now
        )

        var updatedItems = existingItems.filter { $0.id != replacement.id }
        updatedItems.append(replacement)
        updatedItems = recomputeJourneyPlanSchedules(
            affectedDates: [itemToEdit?.userPlannedStartAt, plannedStartAt],
            items: updatedItems
        )

        replaceJourneyPlanItemsUseCase.execute(items: updatedItems)
        plannedStartDate = plannedStartAt
        persistCurrentSetup()
        errorMessage = nil
        recordTripUserActionUseCase.execute(
            status: itemToEdit == nil
            ? "Journey plan created for \(title)"
            : "Journey plan updated for \(title)"
        )
    }

    func deleteJourneyPlanItem(existingItems: [JourneyPlanItem], itemID: UUID) {
        guard let removedItem = existingItems.first(where: { $0.id == itemID }) else { return }
        var updatedItems = existingItems.filter { $0.id != itemID }
        updatedItems = recomputeJourneyPlanSchedules(
            affectedDates: [removedItem.userPlannedStartAt],
            items: updatedItems
        )
        replaceJourneyPlanItemsUseCase.execute(items: updatedItems)
        errorMessage = nil
        recordTripUserActionUseCase.execute(
            status: "Journey plan deleted for \(removedItem.title)"
        )
    }

    private func resolvedLeadTimeMinutes() -> Int {
        (selectedLeadHours * 60) + selectedLeadMinutes
    }

    private func resolvedPlanItemForStart(from items: [JourneyPlanItem]) -> JourneyPlanItem? {
        items
            .filter {
                Calendar.current.isDateInToday($0.userPlannedStartAt) &&
                $0.status == .started
            }
            .sorted { lhs, rhs in
                if lhs.plannedStartAt == rhs.plannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.plannedStartAt < rhs.plannedStartAt
            }
            .first
    }

    private func applyJourneyPlanSelection(_ item: JourneyPlanItem) {
        selectedDestinationName = item.title
        destinationLatitudeText = String(format: "%.7f", item.latitude)
        destinationLongitudeText = String(format: "%.7f", item.longitude)
        selectedJourneyMode = item.selectedJourneyMode
        selectedLeadHours = max(item.leadTimeMinutes / 60, 0)
        selectedLeadMinutes = max(item.leadTimeMinutes % 60, 0)
        plannedStartDate = item.plannedStartAt
        persistCurrentSetup()
    }

    func previewJourneyPlanItem(_ item: JourneyPlanItem) {
        applyJourneyPlanSelection(item)
        errorMessage = nil
    }

    func autoPreviewJourneyPlanItemForTodayIfNeeded(
        items: [JourneyPlanItem],
        isMonitoringActive: Bool
    ) -> JourneyPlanItem? {
        guard !isMonitoringActive else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        if let lastAutoPreview = defaults.object(forKey: lastAutoPreviewJourneyPlanDayKey) as? Date,
           calendar.isDate(lastAutoPreview, inSameDayAs: todayStart) {
            return nil
        }

        let todaysItems = items
            .filter { calendar.isDateInToday($0.userPlannedStartAt) }
            .sorted { lhs, rhs in
                if lhs.plannedStartAt == rhs.plannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.plannedStartAt < rhs.plannedStartAt
            }

        guard let candidate = (todaysItems.first(where: { $0.status == .inProgress }) ??
                               todaysItems.first(where: { $0.status == .started }) ??
                               todaysItems.first) else {
            return nil
        }

        defaults.set(todayStart, forKey: lastAutoPreviewJourneyPlanDayKey)
        return candidate
    }

    private func resolvedEstimatedTravelDuration(
        _ duration: TimeInterval?,
        minimumLeadTimeMinutes: Int? = nil
    ) -> TimeInterval {
        let minimumLeadTime = minimumLeadTimeMinutes ?? resolvedLeadTimeMinutes()
        return max(duration ?? 0, Double(max(minimumLeadTime, 5) * 60))
    }

    private func recomputeJourneyPlanSchedules(
        affectedDates: [Date?],
        items: [JourneyPlanItem]
    ) -> [JourneyPlanItem] {
        let calendar = Calendar.current
        let targetDays = Set(
            affectedDates.compactMap { date in
                date.map { calendar.startOfDay(for: $0) }
            }
        )

        guard !targetDays.isEmpty else {
            return sortedJourneyPlanItems(items)
        }

        var recalculatedItems = items
        for day in targetDays {
            recalculatedItems = recomputeJourneyPlanSchedule(for: day, items: recalculatedItems)
        }
        return sortedJourneyPlanItems(recalculatedItems)
    }

    private func recomputeJourneyPlanSchedule(for date: Date, items: [JourneyPlanItem]) -> [JourneyPlanItem] {
        let calendar = Calendar.current
        let targetItems = items
            .filter { calendar.isDate($0.userPlannedStartAt, inSameDayAs: date) }
            .sorted { lhs, rhs in
                if lhs.userPlannedStartAt == rhs.userPlannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.userPlannedStartAt < rhs.userPlannedStartAt
            }

        var previousEndAt: Date?
        var previousDestinationCoordinate: CLLocationCoordinate2D?
        var recalculatedByID = [UUID: JourneyPlanItem]()

        for item in targetItems {
            if item.status == .completed || item.status == .inProgress {
                recalculatedByID[item.id] = item
                previousEndAt = max(previousEndAt ?? item.approximateEndAt, item.approximateEndAt)
                previousDestinationCoordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
                continue
            }

            let adjustedStartAt: Date
            if let previousEndAt, previousEndAt > item.userPlannedStartAt {
                adjustedStartAt = previousEndAt
            } else {
                adjustedStartAt = item.userPlannedStartAt
            }

            let recalculated = JourneyPlanItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                startLatitude: previousDestinationCoordinate?.latitude,
                startLongitude: previousDestinationCoordinate?.longitude,
                latitude: item.latitude,
                longitude: item.longitude,
                userPlannedStartAt: item.userPlannedStartAt,
                plannedStartAt: adjustedStartAt,
                estimatedTravelDurationSeconds: item.estimatedTravelDurationSeconds,
                selectedJourneyMode: item.selectedJourneyMode,
                leadTimeMinutes: item.leadTimeMinutes,
                status: item.status,
                createdAt: item.createdAt
            )
            recalculatedByID[item.id] = recalculated
            previousEndAt = recalculated.approximateEndAt
            previousDestinationCoordinate = CLLocationCoordinate2D(
                latitude: recalculated.latitude,
                longitude: recalculated.longitude
            )
        }

        return items.map { recalculatedByID[$0.id] ?? $0 }
    }

    private func sortedJourneyPlanItems(_ items: [JourneyPlanItem]) -> [JourneyPlanItem] {
        items.sorted { lhs, rhs in
            if lhs.plannedStartAt == rhs.plannedStartAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.plannedStartAt < rhs.plannedStartAt
        }
    }

    private func plannedStartCoordinate(for item: JourneyPlanItem) -> CLLocationCoordinate2D? {
        guard let startLatitude = item.startLatitude,
              let startLongitude = item.startLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    private func persistCurrentSetup() {
        let payload = PersistedTripSetupState(
            destinationLatitudeText: destinationLatitudeText,
            destinationLongitudeText: destinationLongitudeText,
            selectedDestinationName: selectedDestinationName,
            selectedJourneyModeRaw: selectedJourneyMode.rawValue,
            selectedLeadHours: selectedLeadHours,
            selectedLeadMinutes: selectedLeadMinutes,
            plannedStartDate: plannedStartDate
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
        plannedStartDate = payload.plannedStartDate
    }

    private static let plannedStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct PersistedTripSetupState: Codable {
    let destinationLatitudeText: String
    let destinationLongitudeText: String
    let selectedDestinationName: String?
    let selectedJourneyModeRaw: String
    let selectedLeadHours: Int
    let selectedLeadMinutes: Int
    let plannedStartDate: Date
}
