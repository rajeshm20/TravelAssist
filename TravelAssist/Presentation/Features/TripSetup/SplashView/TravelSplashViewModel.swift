import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import WeatherKit

@MainActor
final class TravelSplashViewModel: ObservableObject {
    struct WeatherPin: Identifiable {
        enum Kind {
            case currentLocation
            case nearbyPlace
            case randomArea
        }

        let id: String
        let kind: Kind
        let name: String
        let coordinate: CLLocationCoordinate2D
        var symbolName: String?
        var temperatureText: String?
    }

    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707),
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    )

    @Published var pins: [WeatherPin] = []
    @Published var showsUserLocation: Bool = false
    @Published var needsWeatherKitSetup: Bool = false
    @Published var isReadyToProceed: Bool = false

    private let locationService: LocationService
    private let weatherService = WeatherService.shared
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshLocation: CLLocation?
    private var lastRefreshAt: Date?
    private var lastRegionCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707)

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

    init(locationService: LocationService) {
        self.locationService = locationService

        locationService.authorizationStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.showsUserLocation = (status == .authorizedAlways || status == .authorizedWhenInUse)
                if status == .denied || status == .restricted {
                    self.applyCountryFallbackRegion()
                    self.refreshPins(around: CLLocation(latitude: self.lastRegionCenter.latitude, longitude: self.lastRegionCenter.longitude))
                }
            }
            .store(in: &cancellables)

        locationService.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    func start() {
        locationService.requestPermissionsIfNeeded()
        locationService.startStandardUpdates()
        locationService.requestOneTimeLocation()

        if let location = locationService.currentLocation {
            handleLocationUpdate(location)
        } else {
            applyCountryFallbackRegion()
            refreshPins(around: CLLocation(latitude: lastRegionCenter.latitude, longitude: lastRegionCenter.longitude))
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        locationService.stopStandardUpdates()
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        setCameraRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18))

        guard shouldRefresh(for: location) else { return }
        lastRefreshLocation = location
        lastRefreshAt = .now
        refreshPins(around: location)
    }

    private func shouldRefresh(for location: CLLocation) -> Bool {
        let minInterval: TimeInterval = 25
        let minDistanceMeters: CLLocationDistance = 180

        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < minInterval {
            return false
        }

        if let lastRefreshLocation, location.distance(from: lastRefreshLocation) < minDistanceMeters {
            return false
        }

        return true
    }

    private func refreshPins(around location: CLLocation) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }

            let current = WeatherPin(
                id: "current",
                kind: .currentLocation,
                name: "You",
                coordinate: location.coordinate,
                symbolName: nil,
                temperatureText: nil
            )

            let randomPins = self.makeRandomPins(around: location.coordinate, count: 5)

            var nearby: [WeatherPin] = []
            do {
                let places = try await self.loadNearbyPlaces(around: location.coordinate)
                nearby = places.prefix(4).enumerated().map { index, place in
                    WeatherPin(
                        id: "nearby-\(index)-\(place.name.lowercased())-\(Int((place.coordinate.latitude * 10_000).rounded()))-\(Int((place.coordinate.longitude * 10_000).rounded()))",
                        kind: .nearbyPlace,
                        name: place.name,
                        coordinate: place.coordinate,
                        symbolName: nil,
                        temperatureText: nil
                    )
                }
            } catch {
                // Local search failure shouldn't block current weather.
                nearby = []
            }

            // Put the most relevant pins first so readiness can unlock quickly after a few calls.
            var updatedPins = [current] + randomPins + nearby
            self.pins = updatedPins
            self.updateReadiness(from: updatedPins)

            let now = Date()
            for idx in updatedPins.indices {
                guard !Task.isCancelled else { return }
                let pin = updatedPins[idx]
                do {
                    let weather = try await self.weather(for: pin.coordinate, now: now)
                    self.needsWeatherKitSetup = false
                    let unit: UnitTemperature = (Locale.current.measurementSystem == .metric) ? .celsius : .fahrenheit
                    let temp = Int(weather.currentWeather.temperature.converted(to: unit).value.rounded())
                    updatedPins[idx].symbolName = self.symbolName(for: weather.currentWeather.condition)
                    updatedPins[idx].temperatureText = "\(temp)°"
                } catch {
                    if self.isAuthError(error) {
                        self.needsWeatherKitSetup = true
                    }
                    updatedPins[idx].symbolName = "cloud.fill"
                }
                self.pins = updatedPins
                self.updateReadiness(from: updatedPins)
            }
        }
    }

    private func updateReadiness(from pins: [WeatherPin]) {
        guard !isReadyToProceed else { return }

        let loadedCount = pins.filter { $0.temperatureText != nil }.count

        if showsUserLocation {
            // Only proceed when the current-location pin has weather.
            if let current = pins.first(where: { $0.id == "current" }),
               current.temperatureText != nil,
               loadedCount >= 4 {
                isReadyToProceed = true
            }
        } else {
            // With no permission, proceed when we have *any* weather (fallback center or nearby).
            if loadedCount >= 3 {
                isReadyToProceed = true
            }
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
        let weather = try await weatherService.weather(for: location)
        cache[key] = CacheEntry(weather: weather, fetchedAt: now)
        return weather
    }

    private func pruneCache(now: Date) {
        cache = cache.filter { now.timeIntervalSince($0.value.fetchedAt) < cacheTTLSeconds }
    }

    private func isAuthError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain.contains("WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors")
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

    private struct NearbyPlace {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private func makeRandomPins(around coordinate: CLLocationCoordinate2D, count: Int) -> [WeatherPin] {
        let centerPoint = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)

        var pins: [WeatherPin] = []
        pins.reserveCapacity(count)

        for idx in 0..<count {
            let meters = Double.random(in: 1_800...9_000)
            let angle = Double.random(in: 0..<(2 * Double.pi))
            let dxMeters = cos(angle) * meters
            let dyMeters = sin(angle) * meters

            let point = MKMapPoint(
                x: centerPoint.x + dxMeters * pointsPerMeter,
                y: centerPoint.y + dyMeters * pointsPerMeter
            )
            let kmText = String(format: "%.1f km", meters / 1_000)
            pins.append(
                WeatherPin(
                    id: "random-\(idx)-\(Int(point.x.rounded()))-\(Int(point.y.rounded()))",
                    kind: .randomArea,
                    name: "Area • \(kmText)",
                    coordinate: point.coordinate,
                    symbolName: nil,
                    temperatureText: nil
                )
            )
        }

        return pins
    }

    private func loadNearbyPlaces(around coordinate: CLLocationCoordinate2D) async throws -> [NearbyPlace] {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )

        let queries: [String] = [
            "Tourist attraction",
            "Park",
            "Museum",
            "Hotel",
            "Airport",
            "Train station",
            "Beach"
        ]

        var collected: [NearbyPlace] = []
        collected.reserveCapacity(10)

        for query in queries {
            guard !Task.isCancelled else { return [] }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                for item in response.mapItems.prefix(3) {
                    guard let name = item.name, !name.isEmpty else { continue }
                    collected.append(NearbyPlace(name: name, coordinate: item.placemark.coordinate))
                }
            } catch {
                continue
            }
        }

        // Dedupe by proximity/name so pins feel distinct.
        var deduped: [NearbyPlace] = []
        var seenNames: Set<String> = []

        for place in collected {
            let normalizedName = place.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seenNames.contains(normalizedName) { continue }

            let isTooClose = deduped.contains(where: { existing in
                let a = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                let b = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                return a.distance(from: b) < 600
            })
            if isTooClose { continue }

            seenNames.insert(normalizedName)
            deduped.append(place)
            if deduped.count >= 6 { break }
        }

        return deduped
    }

    private func applyCountryFallbackRegion() {
        let countryCode = Locale.current.region?.identifier ?? "IN"

        let region: MKCoordinateRegion
        switch countryCode {
        case "IN":
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20.5937, longitude: 78.9629),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        case "US":
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        case "GB":
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 55.3781, longitude: -3.4360),
                span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
            )
        default:
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
            )
        }

        setCameraRegion(center: region.center, span: region.span)
    }

    private func setCameraRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        lastRegionCenter = center
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}
