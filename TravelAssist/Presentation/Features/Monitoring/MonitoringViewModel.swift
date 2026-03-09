import Combine
import Foundation

@MainActor
final class MonitoringViewModel: ObservableObject {
    @Published var distanceText = "--"
    @Published var etaText = "--"
    @Published var statusText = "Waiting for first location..."
    @Published var isMonitoring = false
    @Published var isLoadingInitialSnapshot = false

    private let observeUseCase: ObserveTripStateUseCase
    private let stopUseCase: StopTripMonitoringUseCase
    private var cancellables = Set<AnyCancellable>()
    private var loadingStatusTask: Task<Void, Never>?
    private var hasReceivedSnapshotForCurrentSession = false

    private let loadingStatuses = [
        "Preparing route...",
        "Calculating ETA...",
        "Updating status..."
    ]

    init(observeUseCase: ObserveTripStateUseCase, stopUseCase: StopTripMonitoringUseCase) {
        self.observeUseCase = observeUseCase
        self.stopUseCase = stopUseCase
        bind()
    }

    func stopMonitoring() {
        stopUseCase.execute()
        isMonitoring = false
        isLoadingInitialSnapshot = false
        stopLoadingStatusCycle()
    }

    private func bind() {
        observeUseCase.sessionStream()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                self.isMonitoring = (session != nil)
                self.hasReceivedSnapshotForCurrentSession = false

                if session != nil {
                    self.distanceText = "--"
                    self.etaText = "--"
                    self.isLoadingInitialSnapshot = true
                    self.startLoadingStatusCycle()
                } else {
                    self.distanceText = "--"
                    self.etaText = "--"
                    self.statusText = "No active trip session."
                    self.isLoadingInitialSnapshot = false
                    self.stopLoadingStatusCycle()
                }
            }
            .store(in: &cancellables)

        observeUseCase.snapshotStream()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard let snapshot else {
                    if self.isMonitoring && !self.hasReceivedSnapshotForCurrentSession {
                        if self.statusText.isEmpty {
                            self.statusText = self.loadingStatuses[0]
                        }
                    } else {
                        self.distanceText = "--"
                        self.etaText = "--"
                        self.statusText = "No active trip session."
                        self.isLoadingInitialSnapshot = false
                        self.stopLoadingStatusCycle()
                    }
                    return
                }

                self.hasReceivedSnapshotForCurrentSession = true
                self.isLoadingInitialSnapshot = false
                self.stopLoadingStatusCycle()

                if snapshot.distanceMeters <= 0.5 {
                    self.distanceText = "0 m"
                    self.etaText = "00:00"
                    self.statusText = "Reached destination"
                    return
                }

                self.distanceText = Self.formatDistance(snapshot.distanceMeters)
                self.etaText = Self.formatETA(snapshot.etaSeconds)
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

    private static func formatETA(_ etaSeconds: TimeInterval) -> String {
        let totalMinutes = max(Int((etaSeconds / 60.0).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func startLoadingStatusCycle() {
        stopLoadingStatusCycle()
        statusText = loadingStatuses[0]

        loadingStatusTask = Task { [weak self] in
            guard let self else { return }
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                guard !Task.isCancelled else { return }
                guard self.isMonitoring, self.isLoadingInitialSnapshot else { return }
                index = (index + 1) % self.loadingStatuses.count
                self.statusText = self.loadingStatuses[index]
            }
        }
    }

    private func stopLoadingStatusCycle() {
        loadingStatusTask?.cancel()
        loadingStatusTask = nil
    }
}
