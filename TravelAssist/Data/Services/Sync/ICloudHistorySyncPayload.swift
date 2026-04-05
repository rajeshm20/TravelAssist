import Foundation

struct ICloudHistorySyncPayload: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let sessions: [ICloudHistorySession]

    struct ICloudHistorySession: Codable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        let startLatitude: Double
        let startLongitude: Double
        let destinationLatitude: Double
        let destinationLongitude: Double
        let pointsCount: Int
        let gpxFileName: String
        let completionStatus: JourneyCompletionStatus
        let selectedJourneyMode: JourneyMode
        let finalDetectedActivity: DetectedJourneyActivity
        let activityEvents: [TripActivityEvent]
    }
}

extension ICloudHistorySyncPayload.ICloudHistorySession {
    init(_ session: TripHistorySession, maxActivityEvents: Int) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        startLatitude = session.startLatitude
        startLongitude = session.startLongitude
        destinationLatitude = session.destinationLatitude
        destinationLongitude = session.destinationLongitude
        pointsCount = session.pointsCount
        gpxFileName = session.gpxFileName
        completionStatus = session.completionStatus
        selectedJourneyMode = session.selectedJourneyMode
        finalDetectedActivity = session.finalDetectedActivity
        if session.activityEvents.count <= maxActivityEvents {
            activityEvents = session.activityEvents
        } else {
            activityEvents = Array(session.activityEvents.suffix(maxActivityEvents))
        }
    }

    var domain: TripHistorySession {
        TripHistorySession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude,
            pointsCount: pointsCount,
            gpxFileName: gpxFileName,
            gpxFilePath: "",
            completionStatus: completionStatus,
            selectedJourneyMode: selectedJourneyMode,
            finalDetectedActivity: finalDetectedActivity,
            activityEvents: activityEvents
        )
    }
}

