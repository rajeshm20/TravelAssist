import Combine
import Foundation

@MainActor
final class MonitoringViewModel: ObservableObject {
    @Published var distanceText = "--"
    @Published var etaText = "--"
    @Published var statusText = "Waiting for first location..."
    @Published var isActive = true

    private let observeUseCase: ObserveTripStateUseCase
    private let stopUseCase: StopTripMonitoringUseCase
    private var cancellables = Set<AnyCancellable>()

    init(observeUseCase: ObserveTripStateUseCase, stopUseCase: StopTripMonitoringUseCase) {
        self.observeUseCase = observeUseCase
        self.stopUseCase = stopUseCase
        bind()
    }

    func stopMonitoring() {
        stopUseCase.execute()
        isActive = false
    }

    private func bind() {
        observeUseCase.snapshotStream()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard let snapshot else {
                    self.distanceText = "--"
                    self.etaText = "--"
                    self.statusText = "No active trip session."
                    return
                }

                if snapshot.distanceMeters <= 0.5 {
                    self.distanceText = "0 m"
                    self.etaText = "0 min"
                    self.statusText = "Reached destination"
                    return
                }

                self.distanceText = Self.formatDistance(snapshot.distanceMeters)
                self.etaText = "\(snapshot.etaMinutes) min"
                self.statusText = "Updated \(Self.timeFormatter.string(from: snapshot.updatedAt))"
            }
            .store(in: &cancellables)
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
