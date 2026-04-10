import Combine
import Foundation

final class ICloudJourneyPlanSyncController {
    private let repository: TripMonitoringRepositoryImpl
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cancellables = Set<AnyCancellable>()
    private var presenter: JourneyPlanFilePresenter?
    private var debouncedPushWorkItem: DispatchWorkItem?
    private var lastPushedHash: Int?
    private var isApplyingRemoteUpdate = false

    private let maxSyncedItems = 300

    init(repository: TripMonitoringRepositoryImpl, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults

        encoder.outputFormatting = []

        observeSettingChanges()
        observeJourneyPlanChanges()

        applyEnabledState(isEnabled)
    }

    var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.settingICloudJourneyPlanSyncEnabledKey)
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

    private func observeJourneyPlanChanges() {
        repository.journeyPlanPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.schedulePush(items: items)
            }
            .store(in: &cancellables)
    }

    private func applyEnabledState(_ enabled: Bool) {
        if enabled && isAvailable {
            startPresentingIfNeeded()
            readFromICloudAndMerge()
            schedulePush(items: repository.currentJourneyPlanItemsForSync())
        } else {
            stopPresenting()
        }
    }

    private func startPresentingIfNeeded() {
        guard presenter == nil else { return }
        guard let url = iCloudJourneyPlanFileURL() else { return }
        let newPresenter = JourneyPlanFilePresenter(fileURL: url) { [weak self] in
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

    private func schedulePush(items: [JourneyPlanItem]) {
        guard isEnabled, isAvailable else { return }
        guard !isApplyingRemoteUpdate else { return }

        let deletions = repository.currentJourneyPlanTombstonesForSync()
        let payload = ICloudJourneyPlanSyncPayload(
            schemaVersion: 2,
            exportedAt: .now,
            items: Array(items.prefix(maxSyncedItems)).map(ICloudJourneyPlanSyncPayload.ICloudJourneyPlanItem.init),
            deleted: deletions.isEmpty
                ? nil
                : deletions.map { .init(id: $0.id, deletedAt: $0.deletedAt) }
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
        guard let url = iCloudJourneyPlanFileURL() else { return }

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
        guard let url = iCloudJourneyPlanFileURL() else { return }

        var readError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            guard let payload = try? decoder.decode(ICloudJourneyPlanSyncPayload.self, from: data) else { return }
            let items = payload.items.map(\.domain)
            let deleted = payload.deleted ?? []
            mergeRemoteItems(items, deleted: deleted)
        }
    }

    private func mergeRemoteItems(_ remote: [JourneyPlanItem], deleted: [ICloudJourneyPlanSyncPayload.JourneyPlanTombstone]) {
        guard !remote.isEmpty || !deleted.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingRemoteUpdate = true
            self.repository.mergeJourneyPlanFromICloud(remote, deleted: deleted)
            self.isApplyingRemoteUpdate = false
        }
    }

    private func iCloudJourneyPlanFileURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TravelAssist", isDirectory: true)
            .appendingPathComponent("JourneyPlan.json", isDirectory: false)
    }
}

private final class JourneyPlanFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let onChange: () -> Void

    init(fileURL: URL, onChange: @escaping () -> Void) {
        presentedItemURL = fileURL
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }
}
