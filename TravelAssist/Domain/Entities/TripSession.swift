import CoreLocation
import Foundation

struct TripSession: Identifiable {
    let id: UUID
    let startCoordinate: CLLocationCoordinate2D
    let destinationCoordinate: CLLocationCoordinate2D
    let leadTimeMinutes: Int
    let selectedJourneyMode: JourneyMode
    let startedAt: Date

    init(
        id: UUID = UUID(),
        startCoordinate: CLLocationCoordinate2D,
        destinationCoordinate: CLLocationCoordinate2D,
        leadTimeMinutes: Int,
        selectedJourneyMode: JourneyMode,
        startedAt: Date = .now
    ) {
        self.id = id
        self.startCoordinate = startCoordinate
        self.destinationCoordinate = destinationCoordinate
        self.leadTimeMinutes = leadTimeMinutes
        self.selectedJourneyMode = selectedJourneyMode
        self.startedAt = startedAt
    }
}
