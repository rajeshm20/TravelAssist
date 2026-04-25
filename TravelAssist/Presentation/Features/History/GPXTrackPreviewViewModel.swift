import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class GPXTrackPreviewViewModel: ObservableObject {
    @Published var polyline: MKPolyline?
    @Published var statusText: String?
    @Published var isLoading = false

    private let store = ICloudGPXFileStore()
    private var task: Task<Void, Never>?

    func load(session: TripHistorySession) {
        task?.cancel()
        polyline = nil
        statusText = nil

        guard !session.gpxFileName.isEmpty else {
            statusText = "No GPX file"
            return
        }

        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            let localURL = await self.resolveLocalGPXURL(session: session)
            guard !Task.isCancelled else { return }

            guard let localURL else {
                self.isLoading = false
                self.statusText = "GPX not available"
                return
            }

            do {
                let stored = try Data(contentsOf: localURL)
                let decrypted = try GPXFileCrypto.decryptIfNeeded(stored)
                let track = GPXTrackParser.parse(data: decrypted)
                if track.coordinates.count < 2 {
                    self.polyline = nil
                    self.statusText = "GPX has no track points"
                } else {
                    let polyline = MKPolyline(coordinates: track.coordinates, count: track.coordinates.count)
                    polyline.title = "gpx"
                    self.polyline = polyline
                    self.statusText = "Track points: \(track.coordinates.count)"
                }
            } catch {
                self.polyline = nil
                self.statusText = "Failed to read GPX"
            }
            self.isLoading = false
        }
    }

    private func resolveLocalGPXURL(session: TripHistorySession) async -> URL? {
        if !session.gpxFilePath.isEmpty {
            let url = URL(fileURLWithPath: session.gpxFilePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let url = store.localGPXURLIfExists(fileName: session.gpxFileName) {
            return url
        }

        let syncEnabled = UserDefaults.standard.bool(forKey: AppConstants.settingICloudGPXSyncEnabledKey)
        guard syncEnabled, store.isICloudAvailable() else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [store] in
                let url = try? store.pullICloudFileToLocalIfNeeded(fileName: session.gpxFileName)
                continuation.resume(returning: url)
            }
        }
    }
}
