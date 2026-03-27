import CoreLocation
import Foundation

final class JourneyActivityDetector {
    struct Configuration: Sendable {
        let stationarySpeedMetersPerSecond: Double
        let walkingSpeedMetersPerSecond: Double
        let runningSpeedMetersPerSecond: Double

        let climbMinimumHorizontalSpeedMetersPerSecond: Double
        let climbMaximumHorizontalSpeedMetersPerSecond: Double
        let climbMinimumVerticalDeltaMeters: Double
        let climbMinimumVerticalSpeedMetersPerSecond: Double
        let climbMaximumHorizontalAccuracyMeters: Double
        let climbMaximumVerticalAccuracyMeters: Double

        let climbCandidateStreakRequired: Int
        let climbCandidateMaximumGapSeconds: TimeInterval
        let climbCandidateMinimumSampleIntervalSeconds: TimeInterval

        static let `default` = Configuration(
            stationarySpeedMetersPerSecond: 0.7,
            walkingSpeedMetersPerSecond: 2.2,
            runningSpeedMetersPerSecond: 4.8,
            climbMinimumHorizontalSpeedMetersPerSecond: 0.4,
            climbMaximumHorizontalSpeedMetersPerSecond: 2.8,
            climbMinimumVerticalDeltaMeters: 3.0,
            climbMinimumVerticalSpeedMetersPerSecond: 0.6,
            climbMaximumHorizontalAccuracyMeters: 25,
            climbMaximumVerticalAccuracyMeters: 10,
            climbCandidateStreakRequired: 2,
            climbCandidateMaximumGapSeconds: 6,
            climbCandidateMinimumSampleIntervalSeconds: 0.8
        )
    }

    private let config: Configuration
    private var climbCandidateStreak = 0
    private var lastClimbCandidateAt: Date?

    init(config: Configuration = .default) {
        self.config = config
    }

    func detect(at location: CLLocation, previous: CLLocation?) -> DetectedJourneyActivity {
        let effectiveSpeed = resolveEffectiveHorizontalSpeed(location: location, previous: previous)

        if isClimbCandidate(location: location, previous: previous, effectiveHorizontalSpeed: effectiveSpeed) {
            updateClimbCandidateStreak(with: location.timestamp)
            if climbCandidateStreak >= config.climbCandidateStreakRequired {
                return .climbing
            }
        } else {
            resetClimbCandidateStreak()
        }

        if effectiveSpeed < config.stationarySpeedMetersPerSecond {
            return .stationary
        }
        if effectiveSpeed < config.walkingSpeedMetersPerSecond {
            return .walking
        }
        if effectiveSpeed < config.runningSpeedMetersPerSecond {
            return .running
        }
        return .unknown
    }

    private func resolveEffectiveHorizontalSpeed(location: CLLocation, previous: CLLocation?) -> Double {
        var speed = location.speed
        if !speed.isFinite || speed < 0 {
            speed = 0
        }

        guard let previous else { return speed }
        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return speed }

        if speed <= 0.1 {
            let horizontalDistance = coordinateDistanceMeters(from: previous.coordinate, to: location.coordinate)
            speed = horizontalDistance / dt
        }
        return speed
    }

    private func isClimbCandidate(
        location: CLLocation,
        previous: CLLocation?,
        effectiveHorizontalSpeed: Double
    ) -> Bool {
        guard let previous else { return false }

        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        guard dt >= config.climbCandidateMinimumSampleIntervalSeconds else { return false }
        guard dt > 0 else { return false }

        guard effectiveHorizontalSpeed >= config.climbMinimumHorizontalSpeedMetersPerSecond,
              effectiveHorizontalSpeed <= config.climbMaximumHorizontalSpeedMetersPerSecond else {
            return false
        }

        let currentVerticalAccuracy = location.verticalAccuracy
        let previousVerticalAccuracy = previous.verticalAccuracy
        guard currentVerticalAccuracy >= 0,
              previousVerticalAccuracy >= 0,
              currentVerticalAccuracy <= config.climbMaximumVerticalAccuracyMeters,
              previousVerticalAccuracy <= config.climbMaximumVerticalAccuracyMeters else {
            return false
        }

        guard location.horizontalAccuracy <= config.climbMaximumHorizontalAccuracyMeters,
              previous.horizontalAccuracy <= config.climbMaximumHorizontalAccuracyMeters else {
            return false
        }

        let verticalDelta = abs(location.altitude - previous.altitude)
        let accuracyFloor = max(config.climbMinimumVerticalDeltaMeters, max(currentVerticalAccuracy, previousVerticalAccuracy) * 1.5)
        guard verticalDelta >= accuracyFloor else { return false }

        let verticalSpeed = verticalDelta / dt
        return verticalSpeed >= config.climbMinimumVerticalSpeedMetersPerSecond
    }

    private func updateClimbCandidateStreak(with timestamp: Date) {
        if let last = lastClimbCandidateAt,
           timestamp.timeIntervalSince(last) <= config.climbCandidateMaximumGapSeconds {
            climbCandidateStreak += 1
        } else {
            climbCandidateStreak = 1
        }
        lastClimbCandidateAt = timestamp
    }

    private func resetClimbCandidateStreak() {
        climbCandidateStreak = 0
        lastClimbCandidateAt = nil
    }

    private func coordinateDistanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}

