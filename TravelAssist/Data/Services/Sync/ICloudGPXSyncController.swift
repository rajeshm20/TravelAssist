import Combine
import Foundation

final class ICloudGPXSyncController {
    private let repository: TripMonitoringRepositoryImpl
    private let defaults: UserDefaults
    private let store = ICloudGPXFileStore()

    private var cancellables = Set<AnyCancellable>()
    private var presenter: GPXDirectoryPresenter?
    private let workQueue = DispatchQueue(label: "travelassist.icloud.gpx.sync", qos: .utility)
    private var inFlight = Set<String>()
    private let lock = NSLock()

    init(repository: TripMonitoringRepositoryImpl, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyEnabledState()
            }
            .store(in: &cancellables)

        repository.historyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.handleHistoryChanged(sessions)
            }
            .store(in: &cancellables)

        applyEnabledState()
    }

    private var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.settingICloudGPXSyncEnabledKey)
    }

    private func applyEnabledState() {
        if isEnabled && store.isICloudAvailable() {
            startPresentingIfNeeded()
            handleHistoryChanged(repository.currentHistorySessionsForSync())
        } else {
            stopPresenting()
        }
    }

    private func startPresentingIfNeeded() {
        guard presenter == nil else { return }
        guard let directory = try? store.iCloudGPXDirectory() else { return }
        let newPresenter = GPXDirectoryPresenter(directoryURL: directory) { [weak self] in
            self?.scanICloudDirectory()
        }
        presenter = newPresenter
        NSFileCoordinator.addFilePresenter(newPresenter)
    }

    private func stopPresenting() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        presenter = nil
        lock.lock()
        inFlight.removeAll()
        lock.unlock()
    }

    private func handleHistoryChanged(_ sessions: [TripHistorySession]) {
        guard isEnabled && store.isICloudAvailable() else { return }

        // Push local GPX files
        for session in sessions {
            guard !session.gpxFileName.isEmpty else { continue }

            if !session.gpxFilePath.isEmpty,
               FileManager.default.fileExists(atPath: session.gpxFilePath) {
                scheduleUpload(localPath: session.gpxFilePath, fileName: session.gpxFileName)
            } else {
                scheduleDownload(fileName: session.gpxFileName, sessionID: session.id)
            }
        }
    }

    private func scheduleUpload(localPath: String, fileName: String) {
        guard claim(fileName: fileName) else { return }
        let localURL = URL(fileURLWithPath: localPath, isDirectory: false)

        workQueue.async { [weak self] in
            defer { self?.release(fileName: fileName) }
            do {
                try self?.store.pushLocalFileToICloud(localFileURL: localURL, fileName: fileName)
            } catch {
                // ignore
            }
        }
    }

    private func scheduleDownload(fileName: String, sessionID: UUID) {
        guard claim(fileName: fileName) else { return }
        workQueue.async { [weak self] in
            defer { self?.release(fileName: fileName) }
            do {
                guard let localURL = try self?.store.pullICloudFileToLocalIfNeeded(fileName: fileName) else { return }
                DispatchQueue.main.async {
                    self?.repository.updateHistorySessionGPXPath(id: sessionID, path: localURL.path)
                }
            } catch {
                // ignore
            }
        }
    }

    private func scanICloudDirectory() {
        guard isEnabled && store.isICloudAvailable() else { return }
        guard let directory = try? store.iCloudGPXDirectory(),
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        let fileNames = items
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .map(\.lastPathComponent)

        let sessions = repository.currentHistorySessionsForSync()
        let sessionsByFile = Dictionary(grouping: sessions, by: \.gpxFileName)
        for fileName in fileNames {
            guard let targetSessions = sessionsByFile[fileName], !targetSessions.isEmpty else { continue }
            for session in targetSessions {
                if session.gpxFilePath.isEmpty || !FileManager.default.fileExists(atPath: session.gpxFilePath) {
                    scheduleDownload(fileName: fileName, sessionID: session.id)
                }
            }
        }
    }

    private func claim(fileName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlight.contains(fileName) { return false }
        inFlight.insert(fileName)
        return true
    }

    private func release(fileName: String) {
        lock.lock()
        inFlight.remove(fileName)
        lock.unlock()
    }
}

private final class GPXDirectoryPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let onChange: () -> Void

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = directoryURL
        self.onChange = onChange
        super.init()
    }

    func presentedSubitemDidAppear(at url: URL) {
        onChange()
    }

    func presentedSubitemDidChange(at url: URL) {
        onChange()
    }

    func presentedItemDidChange() {
        onChange()
    }
}

