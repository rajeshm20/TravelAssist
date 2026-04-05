import Foundation

struct ICloudGPXFileStore {
    enum StoreError: Error {
        case iCloudUnavailable
        case fileNotFound
        case failedToDownload
    }

    func isICloudAvailable() -> Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    func localHistoryDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = documents.appendingPathComponent("TripHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func localGPXURL(fileName: String) throws -> URL {
        try localHistoryDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    func localGPXURLIfExists(fileName: String) -> URL? {
        guard let url = try? localGPXURL(fileName: fileName) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func iCloudGPXDirectory() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw StoreError.iCloudUnavailable
        }
        let directory = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TravelAssist", isDirectory: true)
            .appendingPathComponent("GPX", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func iCloudGPXURL(fileName: String) throws -> URL {
        try iCloudGPXDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    func pushLocalFileToICloud(localFileURL: URL, fileName: String) throws {
        let iCloudURL = try iCloudGPXURL(fileName: fileName)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: iCloudURL, options: .forReplacing, error: &coordError) { destination in
            do {
                let data = try Data(contentsOf: localFileURL)
                try data.write(to: destination, options: [.atomic])
            } catch {
                // Ignore write failure.
            }
        }
        if coordError != nil {
            // Ignore coordination failures.
        }
    }

    func pullICloudFileToLocalIfNeeded(fileName: String) throws -> URL {
        if let existing = localGPXURLIfExists(fileName: fileName) {
            return existing
        }

        let iCloudURL = try iCloudGPXURL(fileName: fileName)
        guard FileManager.default.fileExists(atPath: iCloudURL.path) else {
            throw StoreError.fileNotFound
        }

        try ensureDownloaded(iCloudURL)

        let localURL = try localGPXURL(fileName: fileName)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: iCloudURL, options: [], writingItemAt: localURL, options: .forReplacing, error: &coordError) { source, destination in
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: destination, options: [.atomic])
            } catch {
                // Ignore.
            }
        }

        if let existing = localGPXURLIfExists(fileName: fileName) {
            return existing
        }
        throw StoreError.failedToDownload
    }

    private func ensureDownloaded(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = values.ubiquitousItemDownloadingStatus,
           status == .current || status == .downloaded {
            return
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let polled = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = polled?.ubiquitousItemDownloadingStatus,
               status == .current || status == .downloaded {
                return
            }
            Thread.sleep(forTimeInterval: 0.35)
        }

        throw StoreError.failedToDownload
    }
}
