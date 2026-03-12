//
//  TravelAssistWidget.swift
//  TravelAssistWidget
//
//  Created by Rajesh Mani on 09/03/26.
//

import SwiftUI
import WidgetKit
import CoreLocation

struct TravelStatusEntry: TimelineEntry {
    let date: Date
    let distanceText: String
    let etaText: String
    let statusText: String
    let modeSymbolName: String
    let modeText: String
    let distanceProgress: Double
    let timeProgress: Double
}

struct TravelStatusProvider: TimelineProvider {
    private let arrivalDistanceThresholdMeters: Double = 150
    private let staleDataThresholdSeconds: TimeInterval = 180

    func placeholder(in context: Context) -> TravelStatusEntry {
        TravelStatusEntry(
            date: .now,
            distanceText: "2.3 km",
            etaText: "12 min",
            statusText: "Updated just now",
            modeSymbolName: "car.fill",
            modeText: "Car",
            distanceProgress: 0.35,
            timeProgress: 0.30
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

        guard let data = defaults?.data(forKey: "widget.snapshot"),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data) else {
            return TravelStatusEntry(
                date: .now,
                distanceText: "--",
                etaText: "--",
                statusText: "No active trip",
                modeSymbolName: "location.fill",
                modeText: "No trip",
                distanceProgress: 0,
                timeProgress: 0
            )
        }

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
            timeProgress: timeProgress
        )
    }

    private func loadSession(from defaults: UserDefaults?) -> WidgetSessionPayload? {
        guard let data = defaults?.data(forKey: "widget.session") else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSessionPayload.self, from: data)
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
}

private struct ModePresentation {
    let symbolName: String
    let title: String
}

struct TravelStatusWidgetView: View {
    var entry: TravelStatusProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(8)
    }

    private var inlineContent: some View {
        Text("\(Image(systemName: entry.modeSymbolName)) \(entry.etaText) • \(entry.distanceText)")
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
            Text("ETA \(entry.etaText) • \(entry.distanceText)")
                .font(.caption)
                .lineLimit(1)
            ProgressView(value: entry.distanceProgress)
                .progressViewStyle(.linear)
            Text(entry.statusText)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var detailedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TravelAssist")
                .font(.headline)
            Label(entry.modeText, systemImage: entry.modeSymbolName)
                .font(.caption)
                .lineLimit(1)
            progressRow(title: "Distance", value: entry.distanceProgress, trailingText: entry.distanceText)
            progressRow(title: "Time", value: entry.timeProgress, trailingText: entry.etaText)
            Text(entry.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
    let startedAt: Date
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
