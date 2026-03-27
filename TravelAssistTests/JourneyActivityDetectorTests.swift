import CoreLocation
import Foundation
import Testing
@testable import TravelAssist

@Suite("JourneyActivityDetector Tests")
struct JourneyActivityDetectorTests {

    @Test("Indoor altitude jitter does not classify as climbing")
    func testAltitudeJitterClassifiedAsStationary() async throws {
        let detector = JourneyActivityDetector()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let previous = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 12.0, longitude: 77.0),
            altitude: 100,
            horizontalAccuracy: 35,
            verticalAccuracy: 25,
            course: 0,
            speed: 0,
            timestamp: baseTime
        )

        let current = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 12.0, longitude: 77.0),
            altitude: 103,
            horizontalAccuracy: 35,
            verticalAccuracy: 25,
            course: 0,
            speed: 0,
            timestamp: baseTime.addingTimeInterval(2)
        )

        let activity = detector.detect(at: current, previous: previous)
        #expect(activity == .stationary)
    }

    @Test("Requires a cadence (streak) before reporting climbing")
    func testClimbingRequiresConsecutiveSamples() async throws {
        let detector = JourneyActivityDetector()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let start = CLLocationCoordinate2D(latitude: 12.0, longitude: 77.0)
        let moved = CLLocationCoordinate2D(latitude: 12.00005, longitude: 77.00005)

        let sample1Prev = CLLocation(
            coordinate: start,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 1,
            course: 0,
            speed: 1.2,
            timestamp: baseTime
        )

        let sample1 = CLLocation(
            coordinate: moved,
            altitude: 3.6,
            horizontalAccuracy: 5,
            verticalAccuracy: 1,
            course: 0,
            speed: 1.2,
            timestamp: baseTime.addingTimeInterval(4)
        )

        let first = detector.detect(at: sample1, previous: sample1Prev)
        #expect(first != .climbing)

        let sample2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: moved.latitude + 0.00005, longitude: moved.longitude + 0.00005),
            altitude: 7.2,
            horizontalAccuracy: 5,
            verticalAccuracy: 1,
            course: 0,
            speed: 1.2,
            timestamp: baseTime.addingTimeInterval(8)
        )

        let second = detector.detect(at: sample2, previous: sample1)
        #expect(second == .climbing)
    }

    @Test("Elevator-like vertical movement with no horizontal cadence stays stationary")
    func testElevatorDoesNotTriggerClimbing() async throws {
        let detector = JourneyActivityDetector()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinate = CLLocationCoordinate2D(latitude: 12.0, longitude: 77.0)

        let previous = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 1,
            course: 0,
            speed: 0,
            timestamp: baseTime
        )

        let current = CLLocation(
            coordinate: coordinate,
            altitude: 6,
            horizontalAccuracy: 5,
            verticalAccuracy: 1,
            course: 0,
            speed: 0,
            timestamp: baseTime.addingTimeInterval(6)
        )

        let activity = detector.detect(at: current, previous: previous)
        #expect(activity == .stationary)
    }
}
