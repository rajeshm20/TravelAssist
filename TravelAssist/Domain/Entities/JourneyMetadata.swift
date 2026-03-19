import Foundation

enum JourneyMode: String, Codable, CaseIterable, Identifiable {
    case walk
    case run
    case cycle
    case motorbike
    case bus
    case car

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .motorbike: return "Motorbike"
        case .bus: return "Bus"
        case .car: return "Car"
        }
    }

    var symbolName: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "figure.outdoor.cycle"
        case .motorbike: return "motorcycle.fill"
        case .bus: return "bus.fill"
        case .car: return "car.fill"
        }
    }

    var progressStatusText: String {
        switch self {
        case .walk: return "Walking to destination"
        case .run: return "Running to destination"
        case .cycle: return "Cycling to destination"
        case .motorbike: return "Riding to destination"
        case .bus: return "On bus route"
        case .car: return "Driving to destination"
        }
    }
}

enum DetectedJourneyActivity: String, Codable {
    case stationary
    case walking
    case running
    case climbing
    case unknown

    var title: String {
        switch self {
        case .stationary: return "At Rest"
        case .walking: return "Walking"
        case .running: return "Running"
        case .climbing: return "Climbing"
        case .unknown: return "Moving"
        }
    }

    var symbolName: String {
        switch self {
        case .stationary: return "pause.circle"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .climbing: return "figure.climbing"
        case .unknown: return "location.fill"
        }
    }

    var progressStatusText: String {
        switch self {
        case .stationary: return "Idle / At Rest"
        case .walking: return "Walking to destination"
        case .running: return "Running to destination"
        case .climbing: return "Climbing route"
        case .unknown: return "On the way"
        }
    }
}

enum MonitoringRunState: String, Codable {
    case active
    case atRest
}

enum JourneyCompletionStatus: String, Codable {
    case destinationReached
    case journeyFinished
    case cancelledByUser
    case locationTurnedOffBeforeDestination

    var title: String {
        switch self {
        case .destinationReached: return "Destination reached"
        case .journeyFinished: return "Journey finished"
        case .cancelledByUser: return "Cancelled by user"
        case .locationTurnedOffBeforeDestination: return "Location turned off before destination"
        }
    }
}

enum JourneyPlanStatus: String, Codable, CaseIterable {
    case started
    case inProgress
    case completed

    var title: String {
        switch self {
        case .started:
            return "Started"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        }
    }
}

struct JourneyPlanItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let latitude: Double
    let longitude: Double
    let plannedStartAt: Date
    let approximateEndAt: Date
    let estimatedTravelDurationSeconds: TimeInterval
    let selectedJourneyMode: JourneyMode
    let leadTimeMinutes: Int
    let status: JourneyPlanStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String?,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        latitude: Double,
        longitude: Double,
        plannedStartAt: Date,
        approximateEndAt: Date? = nil,
        estimatedTravelDurationSeconds: TimeInterval,
        selectedJourneyMode: JourneyMode,
        leadTimeMinutes: Int,
        status: JourneyPlanStatus = .started,
        createdAt: Date = .now
    ) {
        let resolvedDuration = max(estimatedTravelDurationSeconds, 0)
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.latitude = latitude
        self.longitude = longitude
        self.plannedStartAt = plannedStartAt
        self.approximateEndAt = approximateEndAt ?? plannedStartAt.addingTimeInterval(resolvedDuration)
        self.estimatedTravelDurationSeconds = resolvedDuration
        self.selectedJourneyMode = selectedJourneyMode
        self.leadTimeMinutes = leadTimeMinutes
        self.status = status
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case startLatitude
        case startLongitude
        case latitude
        case longitude
        case plannedStartAt
        case approximateEndAt
        case estimatedTravelDurationSeconds
        case selectedJourneyMode
        case leadTimeMinutes
        case status
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        let startLatitude = try container.decodeIfPresent(Double.self, forKey: .startLatitude)
        let startLongitude = try container.decodeIfPresent(Double.self, forKey: .startLongitude)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let plannedStartAt = try container.decode(Date.self, forKey: .plannedStartAt)
        let selectedJourneyMode = try container.decode(JourneyMode.self, forKey: .selectedJourneyMode)
        let leadTimeMinutes = try container.decode(Int.self, forKey: .leadTimeMinutes)
        let estimatedTravelDurationSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .estimatedTravelDurationSeconds
        ) ?? TimeInterval(max(leadTimeMinutes, 5) * 60)
        let approximateEndAt = try container.decodeIfPresent(Date.self, forKey: .approximateEndAt)
        let status = try container.decodeIfPresent(JourneyPlanStatus.self, forKey: .status) ?? .started
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? plannedStartAt

        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            latitude: latitude,
            longitude: longitude,
            plannedStartAt: plannedStartAt,
            approximateEndAt: approximateEndAt,
            estimatedTravelDurationSeconds: estimatedTravelDurationSeconds,
            selectedJourneyMode: selectedJourneyMode,
            leadTimeMinutes: leadTimeMinutes,
            status: status,
            createdAt: createdAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(startLatitude, forKey: .startLatitude)
        try container.encodeIfPresent(startLongitude, forKey: .startLongitude)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(plannedStartAt, forKey: .plannedStartAt)
        try container.encode(approximateEndAt, forKey: .approximateEndAt)
        try container.encode(estimatedTravelDurationSeconds, forKey: .estimatedTravelDurationSeconds)
        try container.encode(selectedJourneyMode, forKey: .selectedJourneyMode)
        try container.encode(leadTimeMinutes, forKey: .leadTimeMinutes)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
