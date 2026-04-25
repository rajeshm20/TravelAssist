import CoreLocation

enum AppConstants {
    static let appGroupID = "group.com.rajeshmani.TravelAssist"
    static let backgroundRefreshTaskID = "com.rajeshmani.TravelAssist.refresh"
    static let destinationRegionIdentifier = "destination-geofence"
    static let arrivalDistanceThresholdMeters: CLLocationDistance = 150
    static let fakeCallNotificationID = "travelassist.fakecall"

    static let tripProgressNotificationPrefix = "travelassist.trip.progress"
    static let fakeCallNotificationMessage = "This is Travel Assist Support! Your Destination Reached, Thank you!"

    static let settingICloudHistorySyncEnabledKey = "settings.icloud.history.sync.enabled"
    static let settingICloudGPXSyncEnabledKey = "settings.icloud.gpx.sync.enabled"
    static let settingICloudJourneyPlanSyncEnabledKey = "settings.icloud.journeyplan.sync.enabled"
    static let settingBackgroundMonitoringEnabledKey = "settings.location.background.enabled"
}
