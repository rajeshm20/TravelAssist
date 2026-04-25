import Foundation

struct GPXLocalFileStore {
    func localHistoryDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("TripHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        return directory
    }

    func localGPXURL(fileName: String) throws -> URL {
        try localHistoryDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    func localGPXURLIfExists(fileName: String) -> URL? {
        if let migrated = migrateLegacyGPXIfNeeded(fileName: fileName) {
            return migrated
        }
        guard let url = try? localGPXURL(fileName: fileName) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func migrateLegacyGPXIfNeeded(fileName: String) -> URL? {
        let legacyDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TripHistory", isDirectory: true)
        guard let legacyDirectory else { return nil }
        let legacyURL = legacyDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }

        guard let data = try? Data(contentsOf: legacyURL) else { return nil }
        let encrypted: Data
        do {
            encrypted = try GPXFileCrypto.encrypt(data)
        } catch {
            return nil
        }

        guard let newURL = try? localGPXURL(fileName: fileName) else { return nil }
        do {
            try encrypted.write(
                to: newURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try? FileManager.default.removeItem(at: legacyURL)
            return newURL
        } catch {
            return nil
        }
    }
}

