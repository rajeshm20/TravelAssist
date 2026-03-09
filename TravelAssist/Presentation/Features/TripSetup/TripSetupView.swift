import SwiftUI
import MapKit
import Combine

struct TripSetupView: View {
    @ObservedObject var viewModel: TripSetupViewModel
    @StateObject private var monitoringViewModel: MonitoringViewModel
    @State private var isDestinationPickerPresented = false
    @StateObject private var routePreviewViewModel = RoutePreviewViewModel()

    init(
        viewModel: TripSetupViewModel,
        monitoringViewModelBuilder: @escaping () -> MonitoringViewModel
    ) {
        self.viewModel = viewModel
        _monitoringViewModel = StateObject(wrappedValue: monitoringViewModelBuilder())
    }

    var body: some View {
        NavigationStack {
            Form {
                if monitoringViewModel.isMonitoring {
                    Section("Trip Monitoring") {
                        VStack(spacing: 10) {
                            keyValueRow(title: "Distance", value: monitoringViewModel.distanceText)
                            keyValueRow(title: "ETA", value: monitoringViewModel.etaText)
                            keyValueRow(title: "Status", value: monitoringViewModel.statusText)

                            if monitoringViewModel.isLoadingInitialSnapshot {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    Text("Getting live updates...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button("Stop Monitoring") {
                            monitoringViewModel.stopMonitoring()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }

                Section("Destination Coordinates") {
                    Button("Pick from Apple Maps") {
                        isDestinationPickerPresented = true
                    }

                    if let selectedDestinationName = viewModel.selectedDestinationName {
                        Text("Selected: \(selectedDestinationName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Route Preview") {
                    RoutePreviewMapView(viewModel: routePreviewViewModel)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onAppear {
                            routePreviewViewModel.updateDestination(
                                latitudeText: viewModel.destinationLatitudeText,
                                longitudeText: viewModel.destinationLongitudeText
                            )
                        }
                        .onChange(of: viewModel.destinationLatitudeText) { _, _ in
                            routePreviewViewModel.updateDestination(
                                latitudeText: viewModel.destinationLatitudeText,
                                longitudeText: viewModel.destinationLongitudeText
                            )
                        }
                        .onChange(of: viewModel.destinationLongitudeText) { _, _ in
                            routePreviewViewModel.updateDestination(
                                latitudeText: viewModel.destinationLatitudeText,
                                longitudeText: viewModel.destinationLongitudeText
                            )
                        }

                    if let routeStatusMessage = routePreviewViewModel.routeStatusMessage {
                        Text(routeStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Wake-up Lead Time") {
                    Picker("Lead Time", selection: $viewModel.selectedLeadTimeMinutes) {
                        ForEach(viewModel.leadTimeOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }

                    Toggle("Use custom minutes", isOn: $viewModel.useCustomLeadTime)
                    if viewModel.useCustomLeadTime {
                        TextField("Custom minutes", text: $viewModel.customLeadTimeText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("Start Monitoring") {
                        viewModel.startMonitoring()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("TravelAssist")
            .onAppear {
                viewModel.onAppear()
                routePreviewViewModel.onAppear()
            }
            .onDisappear {
                routePreviewViewModel.onDisappear()
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationSearchSheet { name, coordinate in
                    viewModel.applyDestinationFromAppleMaps(name: name, coordinate: coordinate)
                }
            }
        }
    }

    @ViewBuilder
    private func keyValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
        }
    }
}

private struct DestinationSearchSheet: View {
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DestinationSearchViewModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.recentDestinations.isEmpty {
                    Section {
                        ForEach(viewModel.recentDestinations) { destination in
                            Button {
                                let coordinate = CLLocationCoordinate2D(
                                    latitude: destination.latitude,
                                    longitude: destination.longitude
                                )
                                onSelect(destination.title, coordinate)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(destination.title)
                                        .font(.body)
                                    if let subtitle = destination.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear") {
                                viewModel.clearRecentDestinations()
                            }
                            .font(.caption)
                        }
                    }
                }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search for a place or address")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, completion in
                    Button {
                        Task {
                            if let item = await viewModel.resolve(completion) {
                                let name = item.name ?? completion.title
                                viewModel.saveRecentDestination(
                                    title: name,
                                    subtitle: completion.subtitle,
                                    coordinate: item.placemark.coordinate
                                )
                                onSelect(name, item.placemark.coordinate)
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.body)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Fetching location...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .searchable(text: $query, prompt: "Search Apple Maps")
            .onChange(of: query) { value in
                viewModel.updateQuery(value)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.background)
                }
            }
        }
    }
}

private final class DestinationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var recentDestinations: [RecentDestination] = []

    private let completer = MKLocalSearchCompleter()
    private let defaults = UserDefaults.standard
    private let recentDestinationsKey = "tripsetup.recent.destinations"
    private let maxRecentCount = 8

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        loadRecentDestinations()
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            errorMessage = nil
            return
        }
        completer.queryFragment = trimmed
    }

    @MainActor
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else {
                errorMessage = "Could not resolve this place. Try another result."
                return nil
            }
            return mapItem
        } catch {
            errorMessage = "Unable to fetch location from Apple Maps."
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            self?.results = completer.results
            self?.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.results = []
            self?.errorMessage = "Search failed. Check network and try again."
        }
    }

    func saveRecentDestination(title: String, subtitle: String?, coordinate: CLLocationCoordinate2D) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let newDestination = RecentDestination(
            title: trimmedTitle,
            subtitle: subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        var updated = recentDestinations.filter { existing in
            let isSamePlace = abs(existing.latitude - newDestination.latitude) < 0.00001 &&
                abs(existing.longitude - newDestination.longitude) < 0.00001
            return !isSamePlace
        }
        updated.insert(newDestination, at: 0)
        if updated.count > maxRecentCount {
            updated = Array(updated.prefix(maxRecentCount))
        }
        recentDestinations = updated
        persistRecentDestinations(updated)
    }

    func clearRecentDestinations() {
        recentDestinations = []
        defaults.removeObject(forKey: recentDestinationsKey)
    }

    private func loadRecentDestinations() {
        guard let data = defaults.data(forKey: recentDestinationsKey),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data) else {
            recentDestinations = []
            return
        }
        recentDestinations = decoded
    }

    private func persistRecentDestinations(_ destinations: [RecentDestination]) {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        defaults.set(data, forKey: recentDestinationsKey)
    }
}

private struct RecentDestination: Codable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), title: String, subtitle: String?, latitude: Double, longitude: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }
}

private struct RoutePreviewMapView: View {
    @ObservedObject var viewModel: RoutePreviewViewModel

    var body: some View {
        ZStack {
            RoutePreviewUIKitMap(
                currentCoordinate: viewModel.currentCoordinate,
                destinationCoordinate: viewModel.destinationCoordinate,
                routePolyline: viewModel.route?.polyline
            )

            if viewModel.isLoadingRoute {
                ProgressView("Loading route...")
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else if viewModel.destinationCoordinate == nil {
                Text("Select destination to preview route")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct RoutePreviewUIKitMap: UIViewRepresentable {
    let currentCoordinate: CLLocationCoordinate2D?
    let destinationCoordinate: CLLocationCoordinate2D?
    let routePolyline: MKPolyline?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            currentCoordinate: currentCoordinate,
            destinationCoordinate: destinationCoordinate,
            routePolyline: routePolyline
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func update(
            mapView: MKMapView,
            currentCoordinate: CLLocationCoordinate2D?,
            destinationCoordinate: CLLocationCoordinate2D?,
            routePolyline: MKPolyline?
        ) {
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)

            var mapRectToFit: MKMapRect?
            func mergeIntoVisibleRect(_ newRect: MKMapRect) {
                if let existingRect = mapRectToFit {
                    mapRectToFit = existingRect.union(newRect)
                } else {
                    mapRectToFit = newRect
                }
            }

            if let currentCoordinate {
                let annotation = MKPointAnnotation()
                annotation.coordinate = currentCoordinate
                annotation.title = "Current"
                mapView.addAnnotation(annotation)
                mergeIntoVisibleRect(MKMapRect(
                    origin: MKMapPoint(currentCoordinate),
                    size: MKMapSize(width: 0, height: 0)
                ))
            }

            if let destinationCoordinate {
                let annotation = MKPointAnnotation()
                annotation.coordinate = destinationCoordinate
                annotation.title = "Destination"
                mapView.addAnnotation(annotation)
                mergeIntoVisibleRect(MKMapRect(
                    origin: MKMapPoint(destinationCoordinate),
                    size: MKMapSize(width: 0, height: 0)
                ))
            }

            if let routePolyline {
                mapView.addOverlay(routePolyline, level: .aboveRoads)
                mergeIntoVisibleRect(routePolyline.boundingMapRect)
            }

            guard let mapRectToFit, !mapRectToFit.isNull, !mapRectToFit.isEmpty else { return }
            let paddedRect = mapRectToFit.insetBy(
                dx: -max(mapRectToFit.size.width * 0.25, 180),
                dy: -max(mapRectToFit.size.height * 0.30, 180)
            )
            mapView.setVisibleMapRect(
                paddedRect,
                edgePadding: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18),
                animated: true
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemOrange
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

@MainActor
private final class RoutePreviewViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var route: MKRoute?
    @Published var isLoadingRoute = false
    @Published var routeStatusMessage: String?

    private let locationManager = CLLocationManager()
    private var routeTask: Task<Void, Never>?
    private var lastAcceptedLocation: CLLocation?

    private let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 80
    private let maximumLocationAgeSeconds: TimeInterval = 20

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                routeStatusMessage = "Approximate location enabled. Turn on Precise Location for accurate map route."
            }
        } else {
            routeStatusMessage = "Allow location access to preview route from current location."
        }
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
        routeTask?.cancel()
    }

    func updateDestination(latitudeText: String, longitudeText: String) {
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText) else {
            destinationCoordinate = nil
            route = nil
            if !latitudeText.isEmpty || !longitudeText.isEmpty {
                routeStatusMessage = "Enter valid destination coordinates to preview route."
            } else {
                routeStatusMessage = nil
            }
            return
        }

        destinationCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        routeStatusMessage = nil
        refreshRouteIfPossible()
    }

    private func refreshRouteIfPossible() {
        guard let currentCoordinate, let destinationCoordinate else {
            route = nil
            if destinationCoordinate != nil {
                routeStatusMessage = "Waiting for current location..."
            }
            return
        }

        routeTask?.cancel()
        isLoadingRoute = true

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        routeTask = Task { [weak self] in
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled else { return }
                await self?.applyRouteResponse(response)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.applyRouteError(error)
            }
        }
    }

    private func applyRouteResponse(_ response: MKDirections.Response) {
        isLoadingRoute = false
        guard let firstRoute = response.routes.first else {
            route = nil
            routeStatusMessage = "No drivable route found for this destination."
            return
        }
        route = firstRoute
        routeStatusMessage = "Route preview is ready."
    }

    private func applyRouteError(_ error: Error) {
        isLoadingRoute = false
        route = nil
        routeStatusMessage = "Unable to load route preview right now."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.requestLocation()
            if manager.accuracyAuthorization == .reducedAccuracy {
                routeStatusMessage = "Approximate location enabled. Turn on Precise Location for better accuracy."
            }
            refreshRouteIfPossible()
        } else if status == .denied || status == .restricted {
            routeStatusMessage = "Location access denied. Enable it to preview route."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = bestAcceptableLocation(from: locations) else {
            routeStatusMessage = "Waiting for accurate GPS fix..."
            return
        }

        if let previous = lastAcceptedLocation {
            let movedMeters = location.distance(from: previous)
            let jitterThreshold = max(6, min(25, location.horizontalAccuracy * 0.5))
            let speed = max(location.speed, 0)
            if movedMeters < jitterThreshold && speed < 0.8 {
                return
            }
        }

        lastAcceptedLocation = location
        currentCoordinate = location.coordinate
        if manager.accuracyAuthorization != .reducedAccuracy {
            routeStatusMessage = nil
        }
        refreshRouteIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        routeStatusMessage = "Could not read current location for route preview."
    }

    private func bestAcceptableLocation(from locations: [CLLocation]) -> CLLocation? {
        let now = Date()
        return locations
            .filter { location in
                location.horizontalAccuracy >= 0 &&
                location.horizontalAccuracy <= maximumHorizontalAccuracyMeters &&
                abs(location.timestamp.timeIntervalSince(now)) <= maximumLocationAgeSeconds
            }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }
}
