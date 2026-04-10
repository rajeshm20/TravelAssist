import Foundation

struct ICloudJourneyPlanSyncPayload: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let items: [ICloudJourneyPlanItem]
    let deleted: [JourneyPlanTombstone]?

    struct ICloudJourneyPlanItem: Codable {
        let id: UUID
        let title: String
        let subtitle: String?
        let startLatitude: Double?
        let startLongitude: Double?
        let latitude: Double
        let longitude: Double
        let userPlannedStartAt: Date
        let plannedStartAt: Date
        let approximateEndAt: Date
        let estimatedTravelDurationSeconds: TimeInterval
        let selectedJourneyMode: JourneyMode
        let leadTimeMinutes: Int
        let status: JourneyPlanStatus
        let createdAt: Date
        let updatedAt: Date
    }

    struct JourneyPlanTombstone: Codable, Equatable {
        let id: UUID
        let deletedAt: Date
    }
}

extension ICloudJourneyPlanSyncPayload.ICloudJourneyPlanItem {
    init(_ item: JourneyPlanItem) {
        id = item.id
        title = item.title
        subtitle = item.subtitle
        startLatitude = item.startLatitude
        startLongitude = item.startLongitude
        latitude = item.latitude
        longitude = item.longitude
        userPlannedStartAt = item.userPlannedStartAt
        plannedStartAt = item.plannedStartAt
        approximateEndAt = item.approximateEndAt
        estimatedTravelDurationSeconds = item.estimatedTravelDurationSeconds
        selectedJourneyMode = item.selectedJourneyMode
        leadTimeMinutes = item.leadTimeMinutes
        status = item.status
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    var domain: JourneyPlanItem {
        JourneyPlanItem(
            id: id,
            title: title,
            subtitle: subtitle,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            latitude: latitude,
            longitude: longitude,
            userPlannedStartAt: userPlannedStartAt,
            plannedStartAt: plannedStartAt,
            approximateEndAt: approximateEndAt,
            estimatedTravelDurationSeconds: estimatedTravelDurationSeconds,
            selectedJourneyMode: selectedJourneyMode,
            leadTimeMinutes: leadTimeMinutes,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
