import Combine
import CoreLocation
import Foundation
import SwiftUI
import WeatherKit

@MainActor
final class DestinationWeatherViewModel: ObservableObject {
    struct WeatherLine: Equatable {
        let symbolName: String
        let summaryText: String
    }

    private struct WeatherKey: Hashable {
        let latE4: Int
        let lonE4: Int
        let dayStart: Date
    }

    private enum WeatherState: Equatable {
        case loading
        case success(line: WeatherLine, fetchedAt: Date)
        case unavailable(reason: String, fetchedAt: Date)
    }

    @Published private var states: [WeatherKey: WeatherState] = [:]
    private var inFlight: [WeatherKey: Task<Void, Never>] = [:]
    private let service = WeatherService.shared

    func prefetch(items: [JourneyPlanItem], selectedDay: Date) {
        let dayStart = Calendar.current.startOfDay(for: selectedDay)
        var seen = Set<WeatherKey>()
        for item in items {
            let key = weatherKey(for: item.coordinate, dayStart: dayStart)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            requestWeather(for: item.coordinate, dayStart: dayStart)
        }
    }

    func weatherLine(for item: JourneyPlanItem, selectedDay: Date) -> WeatherLine? {
        let dayStart = Calendar.current.startOfDay(for: selectedDay)
        let key = weatherKey(for: item.coordinate, dayStart: dayStart)
        guard let state = states[key] else { return nil }
        switch state {
        case .success(let line, _):
            return line
        case .loading, .unavailable:
            return nil
        }
    }

    func isLoading(for item: JourneyPlanItem, selectedDay: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: selectedDay)
        let key = weatherKey(for: item.coordinate, dayStart: dayStart)
        if case .loading = states[key] {
            return true
        }
        return false
    }

    func unavailableReason(for item: JourneyPlanItem, selectedDay: Date) -> String? {
        let dayStart = Calendar.current.startOfDay(for: selectedDay)
        let key = weatherKey(for: item.coordinate, dayStart: dayStart)
        guard let state = states[key] else { return nil }
        if case .unavailable(let reason, _) = state {
            return reason
        }
        return nil
    }

    func requestWeather(for coordinate: CLLocationCoordinate2D, dayStart: Date) {
        let normalizedDayStart = Calendar.current.startOfDay(for: dayStart)
        let key = weatherKey(for: coordinate, dayStart: normalizedDayStart)

        if let state = states[key] {
            switch state {
            case .success(_, let fetchedAt) where !isStale(fetchedAt: fetchedAt, dayStart: normalizedDayStart):
                return
            case .unavailable(_, let fetchedAt) where !isStale(fetchedAt: fetchedAt, dayStart: normalizedDayStart):
                return
            case .loading:
                return
            default:
                break
            }
        }

        inFlight[key]?.cancel()
        states[key] = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            let fetchedAt = Date()

            let todayStart = Calendar.current.startOfDay(for: Date())
            if normalizedDayStart < todayStart {
                states[key] = .unavailable(reason: "No historical weather", fetchedAt: fetchedAt)
                inFlight[key] = nil
                return
            }

            do {
                let line = try await fetchDailyWeatherLine(for: coordinate, dayStart: normalizedDayStart)
                states[key] = .success(line: line, fetchedAt: fetchedAt)
            } catch {
                states[key] = .unavailable(reason: "Weather unavailable", fetchedAt: fetchedAt)
            }
            inFlight[key] = nil
        }

        inFlight[key] = task
    }

    private func fetchDailyWeatherLine(for coordinate: CLLocationCoordinate2D, dayStart: Date) async throws -> WeatherLine {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let forecast = try await service.weather(for: location, including: .daily)
        let calendar = Calendar.current

        guard let day = forecast.forecast.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) else {
            throw NSError(domain: "weather.no-day", code: 1)
        }

        let unit: UnitTemperature = (Locale.current.measurementSystem == .metric) ? .celsius : .fahrenheit
        let high = Int(day.highTemperature.converted(to: unit).value.rounded())
        let low = Int(day.lowTemperature.converted(to: unit).value.rounded())
        let tempText = "\(high)°/\(low)°"

        let conditionText = day.condition.description.capitalized
        let symbolName = symbolName(for: day.condition)

        let precipitationChancePercent = Int((day.precipitationChance * 100).rounded())
        let precipText = precipitationChancePercent >= 20 ? " • \(precipitationChancePercent)%" : ""

        return WeatherLine(
            symbolName: symbolName,
            summaryText: "\(conditionText) \(tempText)\(precipText)"
        )
    }

    private func symbolName(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear:
            return "sun.max.fill"
        case .partlyCloudy, .mostlyCloudy:
            return "cloud.sun.fill"
        case .cloudy:
            return "cloud.fill"
        case .drizzle, .rain:
            return "cloud.rain.fill"
        case .heavyRain:
            return "cloud.heavyrain.fill"
        case .thunderstorms:
            return "cloud.bolt.rain.fill"
        case .snow, .flurries:
            return "cloud.snow.fill"
        case .sleet, .hail, .freezingRain:
            return "cloud.sleet.fill"
        case .windy:
            return "wind"
        case .foggy, .haze, .smoky:
            return "cloud.fog.fill"
        default:
            return "cloud.fill"
        }
    }

    private func isStale(fetchedAt: Date, dayStart: Date) -> Bool {
        let now = Date()
        let isToday = Calendar.current.isDateInToday(dayStart)
        let ttl: TimeInterval = isToday ? 30 * 60 : 6 * 60 * 60
        return now.timeIntervalSince(fetchedAt) >= ttl
    }

    private func weatherKey(for coordinate: CLLocationCoordinate2D, dayStart: Date) -> WeatherKey {
        WeatherKey(
            latE4: Int((coordinate.latitude * 10_000).rounded()),
            lonE4: Int((coordinate.longitude * 10_000).rounded()),
            dayStart: dayStart
        )
    }

}

private extension JourneyPlanItem {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
