import Combine
import Foundation

@MainActor
final class MonitoringViewModel: ObservableObject {
    @Published var distanceText = "--"
    @Published var etaText = "--"
    @Published var statusText = "Waiting for first location..."
    @Published var detectedModeText = "--"
    @Published var detectedModeSymbol = "location.fill"
    @Published var selectedJourneyModeText = "--"
    @Published var selectedJourneyModeSymbol = "car.fill"
    @Published var stopButtonTitle = "Stop Monitoring"
    @Published var isMonitoring = false
    @Published var isLoadingInitialSnapshot = false
    @Published var historySessions: [TripHistorySession] = []
    @Published var activeSession: TripSession?

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
                let previousSession = self.activeSession
                self.activeSession = session
                self.isMonitoring = (session != nil)

                if session != nil {
                    self.selectedJourneyModeText = session?.selectedJourneyMode.title ?? "--"
                    self.selectedJourneyModeSymbol = session?.selectedJourneyMode.symbolName ?? "car.fill"

                    if previousSession?.id == session?.id {
                        return
                    }

                    self.hasReceivedSnapshotForCurrentSession = false
                    self.stopButtonTitle = "Stop Monitoring"
                    self.distanceText = "--"
                    self.etaText = "--"
                    self.isLoadingInitialSnapshot = true
                    self.startLoadingStatusCycle()
                } else {
                    self.hasReceivedSnapshotForCurrentSession = false
                    self.distanceText = "--"
                    self.etaText = "--"
                    self.statusText = "No active trip session."
                    self.detectedModeText = "--"
                    self.detectedModeSymbol = "location.fill"
                    self.selectedJourneyModeText = "--"
                    self.selectedJourneyModeSymbol = "car.fill"
                    self.stopButtonTitle = "Stop Monitoring"
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
                self.detectedModeText = snapshot.detectedActivity.title
                self.detectedModeSymbol = snapshot.detectedActivity.symbolName

                if snapshot.distanceMeters <= 0.5 {
                    self.distanceText = "0 m"
                    self.etaText = "00 hr 00 min"
                    self.statusText = "Reached destination"
                    self.stopButtonTitle = "Stop Monitoring"
                    return
                }

                self.distanceText = Self.formatDistance(snapshot.distanceMeters)
                self.etaText = Self.formatETA(snapshot.etaSeconds)
                if snapshot.monitoringState == .atRest {
                    self.statusText = "At rest. GPS paused to save battery."
                    self.stopButtonTitle = "Idle / At Rest"
                } else {
                    self.statusText = "Updated \(Self.timeFormatter.string(from: snapshot.updatedAt))"
                    self.stopButtonTitle = "Stop Monitoring"
                }
            }
            .store(in: &cancellables)

        observeUseCase.historyStream()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.historySessions = sessions
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
        return String(format: "%02d hr %02d min", hours, minutes)
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
