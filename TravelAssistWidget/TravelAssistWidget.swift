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
            distanceProgress: 0.35,
            timeProgress: 0.30
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelStatusEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelStatusEntry>) -> Void) {
        let entry = loadEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
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
        let statusText = resolvedStatusText(snapshot: snapshot, etaMinutes: etaMinutes, session: session)
        let distanceProgress = resolvedDistanceProgress(snapshot: snapshot, session: session)
        let timeProgress = resolvedTimeProgress(snapshot: snapshot, session: session)

        return TravelStatusEntry(
            date: snapshot.updatedAt,
            distanceText: distanceText,
            etaText: etaText,
            statusText: statusText,
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
        session: WidgetSessionPayload?
    ) -> String {
        if Date().timeIntervalSince(snapshot.updatedAt) > staleDataThresholdSeconds {
            return "Waiting for fresh location"
        }

        if snapshot.distanceMeters <= arrivalDistanceThresholdMeters {
            return "Reached destination"
        }

        if let leadTimeMinutes = session?.leadTimeMinutes, etaMinutes <= leadTimeMinutes {
            return "Arriving soon"
        }

        return "On the way"
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
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
        Text("ETA \(entry.etaText) • \(entry.distanceText)")
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
                Text("ETA")
                    .font(.system(size: 9, weight: .semibold))
                Text(entry.etaText.replacingOccurrences(of: " ", with: ""))
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(2)
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 4) {
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
    let updatedAt: Date
}

private struct WidgetSessionPayload: Codable {
    let startLatitude: Double?
    let startLongitude: Double?
    let destinationLatitude: Double?
    let destinationLongitude: Double?
    let leadTimeMinutes: Int
    let startedAt: Date
}
