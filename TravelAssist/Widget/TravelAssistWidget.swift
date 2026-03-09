import SwiftUI
import WidgetKit

struct TravelStatusEntry: TimelineEntry {
    let date: Date
    let distanceText: String
    let etaText: String
}

struct TravelStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> TravelStatusEntry {
        TravelStatusEntry(date: .now, distanceText: "2.3 km", etaText: "12 min")
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
        let defaults = UserDefaults(suiteName: "group.com.yourcompany.travelassist")
        guard let data = defaults?.data(forKey: "widget.snapshot"),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data) else {
            return TravelStatusEntry(date: .now, distanceText: "--", etaText: "--")
        }

        let distanceText: String
        if snapshot.distanceMeters < 1000 {
            distanceText = "\(Int(snapshot.distanceMeters)) m"
        } else {
            distanceText = String(format: "%.1f km", snapshot.distanceMeters / 1000)
        }
        let etaText = "\(Int((snapshot.etaSeconds / 60).rounded())) min"

        return TravelStatusEntry(date: snapshot.updatedAt, distanceText: distanceText, etaText: etaText)
    }
}

struct TravelStatusWidgetView: View {
    var entry: TravelStatusProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TravelAssist")
                .font(.headline)
            Text("Distance: \(entry.distanceText)")
            Text("ETA: \(entry.etaText)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(8)
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
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

private struct WidgetSnapshotPayload: Codable {
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let etaSeconds: Double
    let updatedAt: Date
}
