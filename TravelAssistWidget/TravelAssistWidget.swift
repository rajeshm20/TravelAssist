//
//  TravelAssistWidget.swift
//  TravelAssistWidget
//
//  Created by Rajesh Mani on 09/03/26.
//

import SwiftUI
import WidgetKit
import CoreLocation
import MapKit

struct TravelStatusEntry: TimelineEntry {
    let date: Date
    let distanceText: String
    let etaText: String
    let statusText: String
    let modeSymbolName: String
    let modeText: String
    let distanceProgress: Double
    let timeProgress: Double
    let highlightedPlanText: String?
    let planSummaryText: String?
    let hasActiveTrip: Bool
    let shouldShowWidget: Bool
    let nextPlanTitle: String?
    let nextPlanCoordinate: CLLocationCoordinate2D?
}

struct TravelStatusProvider: TimelineProvider {
    private let arrivalDistanceThresholdMeters: Double = 150
    private let staleDataThresholdSeconds: TimeInterval = 180
    fileprivate static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter
    }()

    func placeholder(in context: Context) -> TravelStatusEntry {
        TravelStatusEntry(
            date: .now,
            distanceText: "2.3 km",
            etaText: "12 min",
            statusText: "Updated just now",
            modeSymbolName: "car.fill",
            modeText: "Car",
            distanceProgress: 0.35,
            timeProgress: 0.30,
            highlightedPlanText: "Next: Office • 9:30 AM-10:00 AM",
            planSummaryText: "2 more stops planned today",
            hasActiveTrip: true,
            shouldShowWidget: true,
            nextPlanTitle: "Office",
            nextPlanCoordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelStatusEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelStatusEntry>) -> Void) {
        let entry = loadEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: .now) ?? .now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadEntry() -> TravelStatusEntry {
        let defaults = UserDefaults(suiteName: "group.com.rajeshmani.TravelAssist")
        let session = loadSession(from: defaults)
        let journeyPlan = loadJourneyPlan(from: defaults)
        let highlightedPlan = highlightedPlan(from: journeyPlan, session: session)
        let nextTodayPlan = nextRelevantPlanForToday(from: journeyPlan)
        if let data = defaults?.data(forKey: "widget.snapshot"),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data) {
            let distanceText: String
            if snapshot.distanceMeters < 1000 {
                distanceText = "\(Int(snapshot.distanceMeters)) m"
            } else {
                distanceText = String(format: "%.1f km", snapshot.distanceMeters / 1000)
            }
            let etaMinutes = Int((snapshot.etaSeconds / 60).rounded())
            let etaText = "\(etaMinutes) min"
            let modePresentation = resolvedModePresentation(snapshot: snapshot, session: session)
            let statusText = resolvedStatusText(
                snapshot: snapshot,
                etaMinutes: etaMinutes,
                session: session,
                modePresentation: modePresentation
            )
            let distanceProgress = resolvedDistanceProgress(snapshot: snapshot, session: session)
            let timeProgress = resolvedTimeProgress(snapshot: snapshot, session: session)

            return TravelStatusEntry(
                date: snapshot.updatedAt,
                distanceText: distanceText,
                etaText: etaText,
                statusText: statusText,
                modeSymbolName: modePresentation.symbolName,
                modeText: modePresentation.title,
                distanceProgress: distanceProgress,
                timeProgress: timeProgress,
                highlightedPlanText: highlightedPlan.flatMap {
                    planLine(
                        for: $0,
                        prefix: session?.journeyPlanItemID == $0.id ? "Current" : "Next"
                    )
                },
                planSummaryText: journeyPlanSummary(for: journeyPlan),
                hasActiveTrip: true,
                shouldShowWidget: true,
                nextPlanTitle: nextTodayPlan?.title,
                nextPlanCoordinate: nextTodayPlan.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            )
        }

        guard let nextPlan = nextTodayPlan else {
            return TravelStatusEntry(
                date: .now,
                distanceText: "",
                etaText: "",
                statusText: "",
                modeSymbolName: "location.fill",
                modeText: "",
                distanceProgress: 0,
                timeProgress: 0,
                highlightedPlanText: nil,
                planSummaryText: nil,
                hasActiveTrip: false,
                shouldShowWidget: false,
                nextPlanTitle: nil,
                nextPlanCoordinate: nil
            )
        }

        let modeSymbolName = nextPlan.selectedJourneyModeRaw.flatMap(WidgetJourneyMode.init(rawValue:))?.symbolName ?? "calendar"
        let prefix = nextPlan.status == .inProgress ? "Current" : "Next"
        let modeText = nextPlan.status == .inProgress ? "Trip In Progress" : "Next Trip"

        return TravelStatusEntry(
            date: .now,
            distanceText: Self.timeFormatter.string(from: nextPlan.plannedStartAt),
            etaText: Self.timeFormatter.string(from: nextPlan.approximateEndAt),
            statusText: todayPlanStatusLine(for: journeyPlan),
            modeSymbolName: modeSymbolName,
            modeText: modeText,
            distanceProgress: nextPlan.status == .completed ? 1 : 0,
            timeProgress: 0,
            highlightedPlanText: planLine(for: nextPlan, prefix: prefix),
            planSummaryText: journeyPlanSummary(for: journeyPlan),
            hasActiveTrip: false,
            shouldShowWidget: true,
            nextPlanTitle: nextPlan.title,
            nextPlanCoordinate: CLLocationCoordinate2D(latitude: nextPlan.latitude, longitude: nextPlan.longitude)
        )

    }

    private func loadSession(from defaults: UserDefaults?) -> WidgetSessionPayload? {
        guard let data = defaults?.data(forKey: "widget.session") else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSessionPayload.self, from: data)
    }

    private func loadJourneyPlan(from defaults: UserDefaults?) -> [WidgetJourneyPlanPayload] {
        guard let data = defaults?.data(forKey: "widget.plan"),
              let plan = try? JSONDecoder().decode([WidgetJourneyPlanPayload].self, from: data) else {
            return []
        }
        return plan.sorted { $0.plannedStartAt < $1.plannedStartAt }
    }

    private func resolvedStatusText(
        snapshot: WidgetSnapshotPayload,
        etaMinutes: Int,
        session: WidgetSessionPayload?,
        modePresentation: ModePresentation
    ) -> String {
        if Date().timeIntervalSince(snapshot.updatedAt) > staleDataThresholdSeconds {
            return "Waiting for fresh location"
        }

        if snapshot.distanceMeters <= arrivalDistanceThresholdMeters {
            return "Reached destination"
        }

        if parsedMonitoringState(from: snapshot) == .atRest {
            return "Idle / At Rest"
        }

        if let activity = parsedDetectedActivity(from: snapshot) {
            switch activity {
            case .stationary:
                return "Idle / At Rest"
            case .walking, .running, .climbing:
                return activity.statusText
            case .unknown:
                break
            }
        }

        if let leadTimeMinutes = session?.leadTimeMinutes, etaMinutes <= leadTimeMinutes {
            return "Arriving soon"
        }

        if let selectedMode = parsedSelectedJourneyMode(from: session) {
            return selectedMode.statusText
        }

        return modePresentation.title == "Moving" ? "On the way" : "\(modePresentation.title) in progress"
    }

    private func resolvedDistanceProgress(
        snapshot: WidgetSnapshotPayload,
        session: WidgetSessionPayload?
    ) -> Double {
        if snapshot.distanceMeters <= arrivalDistanceThresholdMeters {
            return 1
        }

        let totalDistance: Double
        if let startLatitude = session?.startLatitude,
           let startLongitude = session?.startLongitude,
           let destinationLatitude = session?.destinationLatitude,
           let destinationLongitude = session?.destinationLongitude {
            let start = CLLocation(latitude: startLatitude, longitude: startLongitude)
            let destination = CLLocation(latitude: destinationLatitude, longitude: destinationLongitude)
            totalDistance = max(start.distance(from: destination), snapshot.distanceMeters)
        } else {
            totalDistance = max(snapshot.distanceMeters, 1)
        }

        return clamped01(1 - (snapshot.distanceMeters / max(totalDistance, 1)))
    }

    private func resolvedTimeProgress(
        snapshot: WidgetSnapshotPayload,
        session: WidgetSessionPayload?
    ) -> Double {
        if snapshot.etaSeconds <= 1 {
            return 1
        }

        guard let startedAt = session?.startedAt else {
            return 0
        }

        let elapsedSeconds = max(0, Date().timeIntervalSince(startedAt))
        let totalDuration = max(elapsedSeconds + snapshot.etaSeconds, 1)
        return clamped01(elapsedSeconds / totalDuration)
    }

    private func clamped01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func resolvedModePresentation(
        snapshot: WidgetSnapshotPayload,
        session: WidgetSessionPayload?
    ) -> ModePresentation {
        if parsedMonitoringState(from: snapshot) == .atRest {
            return ModePresentation(symbolName: "pause.circle", title: "At Rest")
        }

        if let activity = parsedDetectedActivity(from: snapshot), activity != .unknown {
            return ModePresentation(symbolName: activity.symbolName, title: activity.title)
        }

        if let selectedMode = parsedSelectedJourneyMode(from: session) {
            return ModePresentation(symbolName: selectedMode.symbolName, title: selectedMode.title)
        }

        return ModePresentation(symbolName: "location.fill", title: "Moving")
    }

    private func parsedSelectedJourneyMode(from session: WidgetSessionPayload?) -> WidgetJourneyMode? {
        guard let rawValue = session?.selectedJourneyModeRaw else { return nil }
        return WidgetJourneyMode(rawValue: rawValue)
    }

    private func parsedDetectedActivity(from snapshot: WidgetSnapshotPayload) -> WidgetDetectedActivity? {
        guard let rawValue = snapshot.detectedActivityRaw else { return nil }
        return WidgetDetectedActivity(rawValue: rawValue)
    }

    private func parsedMonitoringState(from snapshot: WidgetSnapshotPayload) -> WidgetMonitoringState? {
        guard let rawValue = snapshot.monitoringStateRaw else { return nil }
        return WidgetMonitoringState(rawValue: rawValue)
    }

    private func nextRelevantPlan(from plans: [WidgetJourneyPlanPayload]) -> WidgetJourneyPlanPayload? {
        let now = Date()
        let activePlans = plans.filter { $0.status != .completed }
        return activePlans.first(where: { $0.approximateEndAt >= now }) ??
            activePlans.first ??
            plans.last
    }

    private func nextRelevantPlanForToday(from plans: [WidgetJourneyPlanPayload]) -> WidgetJourneyPlanPayload? {
        let todayPlans = plans
            .filter { Calendar.current.isDateInToday($0.effectivePlannedDay) }
            .sorted { $0.plannedStartAt < $1.plannedStartAt }
        return todayPlans.first(where: { $0.status != .completed })
    }

    private func todayPlanStatusLine(for plans: [WidgetJourneyPlanPayload]) -> String {
        let todayPlans = plans.filter { Calendar.current.isDateInToday($0.effectivePlannedDay) }
        let completedCount = todayPlans.filter { $0.status == .completed }.count
        let remainingCount = todayPlans.filter { $0.status == .started }.count
        let inProgressCount = todayPlans.filter { $0.status == .inProgress }.count

        var segments: [String] = []
        if completedCount > 0 {
            segments.append("Trip \(completedCount) completed")
        }
        if inProgressCount > 0 {
            segments.append("\(inProgressCount) in progress")
        }
        if remainingCount > 0 {
            segments.append("\(remainingCount) remaining")
        }
        return segments.isEmpty ? "Today" : segments.joined(separator: " • ")
    }

    private func journeyPlanSummary(for plans: [WidgetJourneyPlanPayload]) -> String? {
        guard !plans.isEmpty else { return nil }
        let todayPlans = plans.filter { Calendar.current.isDateInToday($0.effectivePlannedDay) }
        if !todayPlans.isEmpty {
            let inProgressCount = todayPlans.filter { $0.status == .inProgress }.count
            let remainingCount = todayPlans.filter { $0.status == .started }.count
            let completedCount = todayPlans.filter { $0.status == .completed }.count

            var segments: [String] = []
            if inProgressCount > 0 {
                segments.append("\(inProgressCount) in progress")
            }
            if remainingCount > 0 {
                segments.append("\(remainingCount) remaining")
            }
            if completedCount > 0 {
                segments.append("\(completedCount) done")
            }
            if !segments.isEmpty {
                return segments.joined(separator: " • ")
            }
        }
        return "\(plans.count) future stop\(plans.count == 1 ? "" : "s") planned"
    }

    private func highlightedPlan(
        from plans: [WidgetJourneyPlanPayload],
        session: WidgetSessionPayload?
    ) -> WidgetJourneyPlanPayload? {
        if let journeyPlanItemID = session?.journeyPlanItemID,
           let currentPlan = plans.first(where: { $0.id == journeyPlanItemID }) {
            return currentPlan
        }
        return nextRelevantPlan(from: plans)
    }

    private func planLine(for plan: WidgetJourneyPlanPayload, prefix: String) -> String {
        "\(prefix): \(plan.title) • \(Self.timeFormatter.string(from: plan.plannedStartAt))-\(Self.timeFormatter.string(from: plan.approximateEndAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ModePresentation {
    let symbolName: String
    let title: String
}

struct TravelStatusWidgetView: View {
    var entry: TravelStatusProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.shouldShowWidget {
            Color.clear
        } else {
            widgetContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .accessoryInline:
            inlineContent
        case .accessoryCircular:
            circularContent
        case .accessoryRectangular:
            accessoryContent
        default:
            detailedContent
        }
    }

    private var inlineContent: some View {
        Text(
            entry.hasActiveTrip
            ? "\(Image(systemName: entry.modeSymbolName)) \(entry.etaText) • \(entry.distanceText)"
            : "\(Image(systemName: entry.modeSymbolName)) \(entry.distanceText)-\(entry.etaText)"
        )
            .lineLimit(1)
            .font(.caption)
    }

    private var circularContent: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: entry.distanceProgress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: entry.modeSymbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text(entry.etaText.replacingOccurrences(of: " ", with: ""))
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(2)
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(entry.modeText, systemImage: entry.modeSymbolName)
                .font(.caption2)
                .lineLimit(1)
            Text(
                entry.hasActiveTrip
                ? "ETA \(entry.etaText) • \(entry.distanceText)"
                : "Start \(entry.distanceText) • End \(entry.etaText)"
            )
                .font(.caption)
                .lineLimit(1)
            ProgressView(value: entry.distanceProgress)
                .progressViewStyle(.linear)
            Text(entry.statusText)
                .font(.caption2)
                .lineLimit(1)
            if let highlightedPlanText = entry.highlightedPlanText {
                Text(highlightedPlanText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let planSummaryText = entry.planSummaryText {
                Text(planSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var detailedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TravelAssist")
                .font(.headline)
            Label(entry.modeText, systemImage: entry.modeSymbolName)
                .font(.caption)
                .lineLimit(1)
            if entry.hasActiveTrip {
                progressRow(title: "Distance", value: entry.distanceProgress, trailingText: entry.distanceText)
                progressRow(title: "Time", value: entry.timeProgress, trailingText: entry.etaText)
            } else {
                progressRow(title: "Planned Start", value: 0, trailingText: entry.distanceText)
                progressRow(title: "Approx. End", value: 0, trailingText: entry.etaText)
            }
            Text(entry.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let highlightedPlanText = entry.highlightedPlanText {
                Text(highlightedPlanText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let planSummaryText = entry.planSummaryText {
                Text(planSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if family == .systemMedium,
               !entry.hasActiveTrip,
               let coordinate = entry.nextPlanCoordinate,
               let title = entry.nextPlanTitle {
                WidgetMapStripView(title: title, coordinate: coordinate)
                    .padding(.top, 2)
            }
        }
    }

    private func progressRow(title: String, value: Double, trailingText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2)
                Spacer(minLength: 8)
                Text(trailingText)
                    .font(.caption2)
            }
            ProgressView(value: value)
                .progressViewStyle(.linear)
        }
    }
}

struct TravelAssistWidget: Widget {
    let kind: String = "TravelAssistWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TravelStatusProvider()) { entry in
            TravelStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Travel ETA")
        .description("Shows distance and ETA for your active trip.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}

private struct WidgetSnapshotPayload: Codable {
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let etaSeconds: Double
    let detectedActivityRaw: String?
    let monitoringStateRaw: String?
    let updatedAt: Date
}

private struct WidgetSessionPayload: Codable {
    let startLatitude: Double?
    let startLongitude: Double?
    let destinationLatitude: Double?
    let destinationLongitude: Double?
    let leadTimeMinutes: Int
    let selectedJourneyModeRaw: String?
    let journeyPlanItemID: UUID?
    let startedAt: Date

    private enum CodingKeys: String, CodingKey {
        case startLatitude
        case startLongitude
        case destinationLatitude
        case destinationLongitude
        case leadTimeMinutes
        case selectedJourneyModeRaw
        case journeyPlanItemID
        case startedAt
    }

    init(
        startLatitude: Double?,
        startLongitude: Double?,
        destinationLatitude: Double?,
        destinationLongitude: Double?,
        leadTimeMinutes: Int,
        selectedJourneyModeRaw: String?,
        journeyPlanItemID: UUID?,
        startedAt: Date
    ) {
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.leadTimeMinutes = leadTimeMinutes
        self.selectedJourneyModeRaw = selectedJourneyModeRaw
        self.journeyPlanItemID = journeyPlanItemID
        self.startedAt = startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startLatitude = try container.decodeIfPresent(Double.self, forKey: .startLatitude)
        startLongitude = try container.decodeIfPresent(Double.self, forKey: .startLongitude)
        destinationLatitude = try container.decodeIfPresent(Double.self, forKey: .destinationLatitude)
        destinationLongitude = try container.decodeIfPresent(Double.self, forKey: .destinationLongitude)
        leadTimeMinutes = try container.decode(Int.self, forKey: .leadTimeMinutes)
        selectedJourneyModeRaw = try container.decodeIfPresent(String.self, forKey: .selectedJourneyModeRaw)
        journeyPlanItemID = try container.decodeIfPresent(UUID.self, forKey: .journeyPlanItemID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
    }
}

private struct WidgetJourneyPlanPayload: Codable {
    let id: UUID
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
    let userPlannedStartAt: Date?
    let plannedStartAt: Date
    let approximateEndAt: Date
    let estimatedTravelDurationSeconds: TimeInterval
    let selectedJourneyModeRaw: String?
    let leadTimeMinutes: Int
    let statusRaw: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case latitude
        case longitude
        case userPlannedStartAt
        case plannedStartAt
        case approximateEndAt
        case estimatedTravelDurationSeconds
        case selectedJourneyModeRaw
        case leadTimeMinutes
        case statusRaw
    }

    var effectivePlannedDay: Date {
        userPlannedStartAt ?? plannedStartAt
    }

    var dayLabel: String {
        if Calendar.current.isDateInToday(effectivePlannedDay) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(effectivePlannedDay) {
            return "Tomorrow"
        }
        return TravelStatusProvider.dayFormatter.string(from: effectivePlannedDay)
    }

    var status: WidgetJourneyPlanStatus {
        guard let statusRaw else { return .started }
        return WidgetJourneyPlanStatus(rawValue: statusRaw) ?? .started
    }

    var statusTitle: String {
        status.title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decode(String.self, forKey: .title)
        let subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let plannedStartAt = try container.decode(Date.self, forKey: .plannedStartAt)
        let userPlannedStartAt = try container.decodeIfPresent(Date.self, forKey: .userPlannedStartAt)
        let leadTimeMinutes = try container.decode(Int.self, forKey: .leadTimeMinutes)
        let estimatedTravelDurationSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .estimatedTravelDurationSeconds
        ) ?? TimeInterval(max(leadTimeMinutes, 5) * 60)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.userPlannedStartAt = userPlannedStartAt
        self.plannedStartAt = plannedStartAt
        self.approximateEndAt = try container.decodeIfPresent(Date.self, forKey: .approximateEndAt)
            ?? plannedStartAt.addingTimeInterval(estimatedTravelDurationSeconds)
        self.estimatedTravelDurationSeconds = estimatedTravelDurationSeconds
        self.selectedJourneyModeRaw = try container.decodeIfPresent(String.self, forKey: .selectedJourneyModeRaw)
        self.leadTimeMinutes = leadTimeMinutes
        self.statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw)
    }
}

private struct WidgetMapStripView: View {
    let title: String
    let coordinate: CLLocationCoordinate2D

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }

    var body: some View {
        Map(coordinateRegion: .constant(region), annotationItems: [PinItem(title: title, coordinate: coordinate)]) { item in
            MapAnnotation(coordinate: item.coordinate) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(radius: 2)
            }
        }
        .allowsHitTesting(false)
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private struct PinItem: Identifiable {
        let id = UUID()
        let title: String
        let coordinate: CLLocationCoordinate2D
    }
}

private enum WidgetJourneyPlanStatus: String, Codable {
    case started
    case inProgress
    case completed

    var title: String {
        switch self {
        case .started:
            return "Planned"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        }
    }
}

private enum WidgetJourneyMode: String, Codable {
    case walk
    case run
    case cycle
    case motorbike
    case bus
    case car

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .motorbike: return "Motorbike"
        case .bus: return "Bus"
        case .car: return "Car"
        }
    }

    var symbolName: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "figure.outdoor.cycle"
        case .motorbike: return "motorcycle.fill"
        case .bus: return "bus.fill"
        case .car: return "car.fill"
        }
    }

    var statusText: String {
        switch self {
        case .walk: return "Walking to destination"
        case .run: return "Running to destination"
        case .cycle: return "Cycling to destination"
        case .motorbike: return "Riding to destination"
        case .bus: return "On bus route"
        case .car: return "Driving to destination"
        }
    }
}

private enum WidgetDetectedActivity: String, Codable {
    case stationary
    case walking
    case running
    case climbing
    case unknown

    var title: String {
        switch self {
        case .stationary: return "At Rest"
        case .walking: return "Walking"
        case .running: return "Running"
        case .climbing: return "Climbing"
        case .unknown: return "Moving"
        }
    }

    var symbolName: String {
        switch self {
        case .stationary: return "pause.circle"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .climbing: return "figure.climbing"
        case .unknown: return "location.fill"
        }
    }

    var statusText: String {
        switch self {
        case .stationary: return "Idle / At Rest"
        case .walking: return "Walking to destination"
        case .running: return "Running to destination"
        case .climbing: return "Climbing route"
        case .unknown: return "On the way"
        }
    }
}

private enum WidgetMonitoringState: String, Codable {
    case active
    case atRest
}
