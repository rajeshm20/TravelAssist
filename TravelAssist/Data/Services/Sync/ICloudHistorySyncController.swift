import Combine
import Foundation

final class ICloudHistorySyncController {
    private let repository: TripMonitoringRepositoryImpl
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cancellables = Set<AnyCancellable>()
    private var presenter: HistoryFilePresenter?
    private var debouncedPushWorkItem: DispatchWorkItem?
    private var lastPushedHash: Int?
    private var isApplyingRemoteUpdate = false

    private let maxSyncedSessions = 50
    private let maxSyncedActivityEventsPerSession = 200

    init(repository: TripMonitoringRepositoryImpl, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults

        encoder.outputFormatting = []

        observeSettingChanges()
        observeHistoryChanges()

        // Apply initial state
        applyEnabledState(isEnabled)
    }

    var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.settingICloudHistorySyncEnabledKey)
    }

    var isAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    private func observeSettingChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyEnabledState(self.isEnabled)
            }
            .store(in: &cancellables)
    }

    private func observeHistoryChanges() {
        repository.historyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.schedulePush(sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private func applyEnabledState(_ enabled: Bool) {
        if enabled && isAvailable {
            startPresentingIfNeeded()
            // Try to pull latest from iCloud as soon as we enable.
            readFromICloudAndMerge()
            // And push our current view (merge might update it again).
            schedulePush(sessions: repository.currentHistorySessionsForSync())
        } else {
            stopPresenting()
        }
    }

    private func startPresentingIfNeeded() {
        guard presenter == nil else { return }
        guard let url = iCloudHistoryFileURL() else { return }
        let newPresenter = HistoryFilePresenter(fileURL: url) { [weak self] in
            self?.readFromICloudAndMerge()
        }
        presenter = newPresenter
        NSFileCoordinator.addFilePresenter(newPresenter)
    }

    private func stopPresenting() {
        debouncedPushWorkItem?.cancel()
        debouncedPushWorkItem = nil
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        presenter = nil
    }

    private func schedulePush(sessions: [TripHistorySession]) {
        guard isEnabled, isAvailable else { return }
        guard !isApplyingRemoteUpdate else { return }

        let payload = ICloudHistorySyncPayload(
            schemaVersion: 1,
            exportedAt: .now,
            sessions: Array(sessions.prefix(maxSyncedSessions)).map {
                ICloudHistorySyncPayload.ICloudHistorySession($0, maxActivityEvents: maxSyncedActivityEventsPerSession)
            }
        )

        guard let data = try? encoder.encode(payload) else { return }
        let hash = data.hashValue
        if lastPushedHash == hash { return }

        debouncedPushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pushToICloud(data: data, hash: hash)
        }
        debouncedPushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    private func pushToICloud(data: Data, hash: Int) {
        guard isEnabled, isAvailable else { return }
        guard let url = iCloudHistoryFileURL() else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        var writeError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &writeError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: [.atomic])
            } catch {
                // Ignore write failures (common when iCloud is not configured yet).
            }
        }
        if writeError == nil {
            lastPushedHash = hash
        }
    }

    private func readFromICloudAndMerge() {
        guard isEnabled, isAvailable else { return }
        guard let url = iCloudHistoryFileURL() else { return }

        var readError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            guard let payload = try? decoder.decode(ICloudHistorySyncPayload.self, from: data) else { return }
            let sessions = payload.sessions.map(\.domain)
            mergeRemoteHistory(sessions)
        }
    }

    private func mergeRemoteHistory(_ remote: [TripHistorySession]) {
        guard !remote.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingRemoteUpdate = true
            self.repository.mergeHistoryFromICloud(remote)
            self.isApplyingRemoteUpdate = false
        }
    }

    private func iCloudHistoryFileURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TravelAssist", isDirectory: true)
            .appendingPathComponent("SessionHistory.json", isDirectory: false)
    }
}

private final class HistoryFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let onChange: () -> Void

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = fileURL
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }
}
