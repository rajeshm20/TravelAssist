import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import WeatherKit

@MainActor
final class RouteWeatherViewModel: ObservableObject {
    struct WeatherLine: Equatable {
        let symbolName: String
        let title: String
        let detail: String
    }

    struct WeatherMarker {
        let coordinate: CLLocationCoordinate2D
        let symbolName: String
        let title: String
        let subtitle: String?
        let isSevere: Bool
    }

    @Published var currentLine: WeatherLine?
    @Published var markers: [WeatherMarker] = []
    @Published var needsWeatherKitSetup: Bool = false

    private let service = WeatherService.shared
    private let geocoder = CLGeocoder()
    private var task: Task<Void, Never>?
    private var lastRouteSignature: String?
    private var lastCurrentSignature: String?
    private var lastRouteRefreshedAt: Date?
    private var lastCurrentRefreshedAt: Date?

    private struct CacheKey: Hashable {
        let latE3: Int
        let lonE3: Int
    }

    private struct CacheEntry {
        let weather: Weather
        let fetchedAt: Date
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private let cacheTTLSeconds: TimeInterval = 15 * 60
    private let refreshMinIntervalSeconds: TimeInterval = 5 * 60

    private struct PlaceEntry {
        let name: String
        let fetchedAt: Date
    }

    private var placeCache: [CacheKey: PlaceEntry] = [:]
    private let placeCacheTTLSeconds: TimeInterval = 60 * 60

    func refresh(
        currentCoordinate: CLLocationCoordinate2D?,
        route: MKRoute?,
        now: Date = .now
    ) {
        let currentSignature = signatureForCurrent(currentCoordinate)
        let routeSignature = signatureForRoute(route: route)

        let shouldRefreshCurrent: Bool = {
            if currentSignature == nil { return false }
            if currentSignature != lastCurrentSignature { return true }
            guard let lastCurrentRefreshedAt else { return true }
            return now.timeIntervalSince(lastCurrentRefreshedAt) >= refreshMinIntervalSeconds
        }()

        let shouldRefreshRoute: Bool = {
            if routeSignature == nil { return false }
            if routeSignature != lastRouteSignature { return true }
            guard let lastRouteRefreshedAt else { return true }
            return now.timeIntervalSince(lastRouteRefreshedAt) >= refreshMinIntervalSeconds
        }()

        guard shouldRefreshCurrent || shouldRefreshRoute else { return }

        if shouldRefreshCurrent {
            lastCurrentSignature = currentSignature
            lastCurrentRefreshedAt = now
        }
        if shouldRefreshRoute {
            lastRouteSignature = routeSignature
            lastRouteRefreshedAt = now
        }

        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await self.load(
                currentCoordinate: currentCoordinate,
                route: route,
                now: now,
                refreshCurrent: shouldRefreshCurrent,
                refreshRoute: shouldRefreshRoute
            )
        }
    }

    private func load(
        currentCoordinate: CLLocationCoordinate2D?,
        route: MKRoute?,
        now: Date,
        refreshCurrent: Bool,
        refreshRoute: Bool
    ) async {
        if refreshRoute {
            markers = []
        }

        guard let currentCoordinate else {
            if refreshCurrent {
                currentLine = nil
            }
            return
        }

        if refreshCurrent {
            do {
                let currentWeather = try await weather(for: currentCoordinate, now: now)
                needsWeatherKitSetup = false
                currentLine = WeatherLine(
                    symbolName: symbolName(for: currentWeather.currentWeather.condition),
                    title: "Current",
                    detail: currentDetailText(from: currentWeather.currentWeather)
                )
            } catch {
                if isAuthError(error) {
                    needsWeatherKitSetup = true
                    currentLine = WeatherLine(symbolName: "exclamationmark.triangle.fill", title: "Weather", detail: "WeatherKit not enabled")
                } else {
                    currentLine = nil
                }
            }
        }

        guard refreshRoute, let route else { return }
        let sampled = sampleAlong(route.polyline, maxPoints: routeSampleBudget(for: route))
        guard sampled.count >= 2 else { return }

        let travelSeconds = max(route.expectedTravelTime, 1)
        var routeMarkers: [WeatherMarker] = []
        routeMarkers.reserveCapacity(sampled.count)
        var seenPlaces: Set<String> = []

        for (index, coordinate) in sampled.enumerated() {
            guard !Task.isCancelled else { return }
            if index == 0 { continue } // "Current" is already shown separately.
            let fraction = Double(index) / Double(max(sampled.count - 1, 1))
            let expectedAt = now.addingTimeInterval(travelSeconds * fraction)

            do {
                let weather = try await weather(for: coordinate, now: now)
                let hour: any WeatherProtocol
                if let nearest = nearestHour(in: weather.hourlyForecast, to: expectedAt) {
                    hour = nearest
                } else {
                    hour = weather.currentWeather
                }
                let unit: UnitTemperature = (Locale.current.measurementSystem == .metric) ? .celsius : .fahrenheit
                let temp = Int(hour.temperature.converted(to: unit).value.rounded())
                let place = await placeName(for: coordinate, now: now)
                let placeTitle = (place?.isEmpty == false) ? place! : "Along route"
                let placeKey = placeTitle.lowercased()
                if index != sampled.count - 1, seenPlaces.contains(placeKey) {
                    continue
                }
                seenPlaces.insert(placeKey)
                let subtitle = routeMarkerSubtitle(from: hour, expectedAt: expectedAt)
                routeMarkers.append(
                    WeatherMarker(
                        coordinate: coordinate,
                        symbolName: symbolName(for: hour.condition),
                        title: "\(placeTitle) \(temp)°",
                        subtitle: subtitle,
                        isSevere: isSevereTravelWeather(hour: hour)
                    )
                )
            } catch {
                if isAuthError(error) {
                    needsWeatherKitSetup = true
                    markers = []
                    return
                }
                continue
            }
        }

        markers = routeMarkers.uniquedByProximity()

        // Try to augment with severe alerts using a low call budget (start/mid/end).
        await loadAlertsIfAvailable(sampled: sampled, travelSeconds: travelSeconds, now: now)
    }

    private func loadAlertsIfAvailable(sampled: [CLLocationCoordinate2D], travelSeconds: TimeInterval, now: Date) async {
        guard !sampled.isEmpty else { return }
        let indices: [Int] = {
            if sampled.count <= 2 { return Array(sampled.indices) }
            return [0, sampled.count / 2, sampled.count - 1]
        }()

        var alertMarkers: [WeatherMarker] = []

        for idx in indices {
            guard !Task.isCancelled else { return }
            let coordinate = sampled[idx]
            do {
                let weather = try await weather(for: coordinate, now: now)
                guard let alerts = weather.weatherAlerts, !alerts.isEmpty else { continue }

                let expectedAt = now.addingTimeInterval(travelSeconds * (Double(idx) / Double(max(sampled.count - 1, 1))))
                let severe = alerts.first(where: { isLikelyTravelImpactAlert($0, around: expectedAt) })
                guard let severe else { continue }

                let title = severe.summary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                alertMarkers.append(
                    WeatherMarker(
                        coordinate: coordinate,
                        symbolName: "exclamationmark.triangle.fill",
                        title: title.isEmpty ? "Weather alert" : title,
                        subtitle: "Possible travel impact",
                        isSevere: true
                    )
                )
            } catch {
                continue
            }
        }

        if !alertMarkers.isEmpty {
            // Merge + dedupe by coordinate proximity.
            let merged = (markers + alertMarkers).uniquedByProximity()
            markers = merged
        }
    }

    private func weather(for coordinate: CLLocationCoordinate2D, now: Date) async throws -> Weather {
        pruneCache(now: now)
        let key = CacheKey(
            latE3: Int((coordinate.latitude * 1_000).rounded()),
            lonE3: Int((coordinate.longitude * 1_000).rounded())
        )
        if let entry = cache[key], now.timeIntervalSince(entry.fetchedAt) < cacheTTLSeconds {
            return entry.weather
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await service.weather(for: location)
        cache[key] = CacheEntry(weather: weather, fetchedAt: now)
        return weather
    }

    private func signatureForCurrent(_ currentCoordinate: CLLocationCoordinate2D?) -> String? {
        guard let currentCoordinate else { return nil }
        return "\(Int((currentCoordinate.latitude * 10_000).rounded())):\(Int((currentCoordinate.longitude * 10_000).rounded()))"
    }

    private func signatureForRoute(route: MKRoute?) -> String? {
        guard let route else { return nil }
        let end = route.polyline.coordinateAtFraction(1.0)
        let endKey = "\(Int((end.latitude * 10_000).rounded())):\(Int((end.longitude * 10_000).rounded()))"
        let lengthKey = "\(Int(route.distance.rounded()))"
        return "end:\(endKey)-d:\(lengthKey)"
    }

    private func pruneCache(now: Date) {
        cache = cache.filter { now.timeIntervalSince($0.value.fetchedAt) < cacheTTLSeconds }
    }

    private func placeName(for coordinate: CLLocationCoordinate2D, now: Date) async -> String? {
        prunePlaceCache(now: now)
        let key = CacheKey(
            latE3: Int((coordinate.latitude * 1_000).rounded()),
            lonE3: Int((coordinate.longitude * 1_000).rounded())
        )
        if let entry = placeCache[key], now.timeIntervalSince(entry.fetchedAt) < placeCacheTTLSeconds {
            return entry.name
        }

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            let placemark = placemarks.first
            let name = placemark?.locality ??
                placemark?.subAdministrativeArea ??
                placemark?.administrativeArea ??
                placemark?.name
            guard let name, !name.isEmpty else { return nil }
            placeCache[key] = PlaceEntry(name: name, fetchedAt: now)
            return name
        } catch {
            return nil
        }
    }

    private func prunePlaceCache(now: Date) {
        placeCache = placeCache.filter { now.timeIntervalSince($0.value.fetchedAt) < placeCacheTTLSeconds }
    }

    private func isAuthError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain.contains("WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors")
    }

    private func routeSampleBudget(for route: MKRoute) -> Int {
        let seconds = max(route.expectedTravelTime, 0)
        if seconds >= (24 * 60 * 60) { return 9 }
        if seconds >= (10 * 60 * 60) { return 7 }
        return 5
    }

    private func sampleAlong(_ polyline: MKPolyline, maxPoints: Int) -> [CLLocationCoordinate2D] {
        let coordinates = polyline.coordinates()
        guard coordinates.count >= 2 else { return coordinates }

        let totalDistance = totalDistanceMeters(coordinates)
        if totalDistance <= 0 { return [coordinates.first!, coordinates.last!].compactMap { $0 } }

        let clLocations = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(clLocations.count)
        for idx in 1..<clLocations.count {
            cumulative.append(cumulative[idx - 1] + clLocations[idx].distance(from: clLocations[idx - 1]))
        }

        let count = max(2, min(maxPoints, 9))
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let target = totalDistance * (Double(i) / Double(count - 1))
            if let idx = cumulative.firstIndex(where: { $0 >= target }) {
                result.append(coordinates[idx])
            } else if let last = coordinates.last {
                result.append(last)
            }
        }

        return result.uniquedByProximity()
    }

    private func totalDistanceMeters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var total: Double = 0
        var prev = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for c in coordinates.dropFirst() {
            let next = CLLocation(latitude: c.latitude, longitude: c.longitude)
            total += next.distance(from: prev)
            prev = next
        }
        return total
    }

    private func nearestHour(in forecast: Forecast<HourWeather>, to date: Date) -> HourWeather? {
        forecast.forecast.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func currentDetailText(from current: CurrentWeather) -> String {
        let unit: UnitTemperature = (Locale.current.measurementSystem == .metric) ? .celsius : .fahrenheit
        let temp = Int(current.temperature.converted(to: unit).value.rounded())
        let windKph = Int(current.wind.speed.converted(to: .kilometersPerHour).value.rounded())
        let windText = windKph >= 35 ? " • \(windKph) km/h" : ""
        return "\(current.condition.description.capitalized) \(temp)°\(windText)"
    }

    private func findingFor(
        hour: WeatherProtocol,
        at expectedAt: Date,
        coordinate: CLLocationCoordinate2D
    ) -> (Severity, WeatherMarker?) {
        let condition = hour.condition
        let wind = hour.wind.speed.converted(to: .kilometersPerHour).value

        // Basic travel-impact heuristics (best-effort).
        let isThunder = condition == .thunderstorms
        let isHeavyRain = condition == .heavyRain
        let isRain = condition == .rain || condition == .drizzle || isHeavyRain
        let isSnow = condition == .snow || condition == .flurries || condition == .sleet || condition == .hail || condition == .freezingRain
        let isHighWind = wind >= 45

        let minutesFromNow = max(Int((expectedAt.timeIntervalSinceNow / 60).rounded()), 0)
        let timeHint = minutesFromNow > 0 ? "in ~\(minutesFromNow) min" : "soon"

        if isThunder || isHeavyRain || isHighWind || isSnow {
            let (symbol, title): (String, String) = {
                if isThunder { return ("cloud.bolt.rain.fill", "Thunderstorms \(timeHint)") }
                if isHeavyRain { return ("cloud.heavyrain.fill", "Heavy rain \(timeHint)") }
                if isHighWind { return ("wind", "High winds \(timeHint)") }
                return ("cloud.snow.fill", "Snow/ice \(timeHint)")
            }()
            let severe = isThunder || isHeavyRain || isHighWind || isSnow
            return (
                severe ? .severe : .caution,
                WeatherMarker(
                    coordinate: coordinate,
                    symbolName: symbol,
                    title: title,
                    subtitle: nil,
                    isSevere: severe
                )
            )
        }

        if isRain {
            return (.caution, nil)
        }

        return (.normal, nil)
    }

    private func hourDetailText(from hour: WeatherProtocol, expectedAt: Date) -> String {
        let unit: UnitTemperature = (Locale.current.measurementSystem == .metric) ? .celsius : .fahrenheit
        let temp = Int(hour.temperature.converted(to: unit).value.rounded())
        let windKph = Int(hour.wind.speed.converted(to: .kilometersPerHour).value.rounded())
        let time = Self.timeFormatter.string(from: expectedAt)
        let windText = windKph >= 35 ? " • \(windKph) km/h" : ""
        return "\(hour.condition.description.capitalized) \(temp)° • \(time)\(windText)"
    }

    private func routeMarkerSubtitle(from hour: WeatherProtocol, expectedAt: Date) -> String {
        let windKph = Int(hour.wind.speed.converted(to: .kilometersPerHour).value.rounded())
        let time = Self.timeFormatter.string(from: expectedAt)
        let windText = windKph >= 35 ? " • \(windKph) km/h" : ""
        return "\(hour.condition.description.capitalized) • \(time)\(windText)"
    }

    private func isSevereTravelWeather(hour: WeatherProtocol) -> Bool {
        let condition = hour.condition
        let wind = hour.wind.speed.converted(to: .kilometersPerHour).value
        let isThunder = condition == .thunderstorms
        let isHeavyRain = condition == .heavyRain
        let isSnow = condition == .snow || condition == .flurries || condition == .sleet || condition == .hail || condition == .freezingRain
        let isHighWind = wind >= 45
        return isThunder || isHeavyRain || isSnow || isHighWind
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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

    private func isLikelyTravelImpactAlert(_ alert: WeatherAlert, around date: Date) -> Bool {
        let severity = alert.severity
        if severity == .severe || severity == .extreme {
            return true
        }

        let summary = alert.summary.lowercased()
        let keywords = ["flood", "cyclone", "hurricane", "tornado", "storm", "tsunami", "wildfire", "extreme"]
        if keywords.contains(where: { summary.contains($0) }) {
            return true
        }

        return false
    }

    private enum Severity: Int, Comparable {
        case normal = 0
        case caution = 1
        case severe = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

private protocol WeatherProtocol {
    var condition: WeatherCondition { get }
    var temperature: Measurement<UnitTemperature> { get }
    var wind: Wind { get }
}

extension CurrentWeather: WeatherProtocol {}
extension HourWeather: WeatherProtocol {}

private extension Array where Element == CLLocationCoordinate2D {
    func uniquedByProximity(minMeters: CLLocationDistance = 600) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for coordinate in self {
            if let last = result.last {
                let d = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                if d < minMeters { continue }
            }
            result.append(coordinate)
        }
        return result
    }
}

private extension Array where Element == RouteWeatherViewModel.WeatherMarker {
    func uniquedByProximity(minMeters: CLLocationDistance = 700) -> [RouteWeatherViewModel.WeatherMarker] {
        var result: [RouteWeatherViewModel.WeatherMarker] = []
        for marker in self {
            if let last = result.last {
                let d = CLLocation(latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude)
                    .distance(from: CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude))
                if d < minMeters { continue }
            }
            result.append(marker)
        }
        return result
    }
}

private extension MKPolyline {
    func coordinates() -> [CLLocationCoordinate2D] {
        let count = pointCount
        guard count > 0 else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords.filter { CLLocationCoordinate2DIsValid($0) }
    }

    func coordinateAtFraction(_ fraction: Double) -> CLLocationCoordinate2D {
        let coords = coordinates()
        guard !coords.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let clamped = max(0, min(1, fraction))
        let idx = Int((Double(coords.count - 1) * clamped).rounded())
        return coords[max(0, min(idx, coords.count - 1))]
    }
}
