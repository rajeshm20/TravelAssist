import SwiftUI
import MapKit
import Combine

struct TripSetupView: View {
    @ObservedObject var viewModel: TripSetupViewModel
    let monitoringViewModelBuilder: () -> MonitoringViewModel
    @State private var isDestinationPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination Coordinates") {
                    Button("Pick from Apple Maps") {
                        isDestinationPickerPresented = true
                    }

                    if let selectedDestinationName = viewModel.selectedDestinationName {
                        Text("Selected: \(selectedDestinationName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Latitude", text: $viewModel.destinationLatitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $viewModel.destinationLongitudeText)
                        .keyboardType(.numbersAndPunctuation)
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
            .navigationDestination(isPresented: $viewModel.isMonitoringScreenPresented) {
                MonitoringView(viewModel: monitoringViewModelBuilder())
            }
            .onAppear {
                viewModel.onAppear()
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationSearchSheet { name, coordinate in
                    viewModel.applyDestinationFromAppleMaps(name: name, coordinate: coordinate)
                }
            }
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
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search for a place or address")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, completion in
                    Button {
                        Task {
                            if let item = await viewModel.resolve(completion) {
                                let name = item.name ?? completion.title
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

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
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
}
