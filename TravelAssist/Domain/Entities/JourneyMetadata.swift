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
