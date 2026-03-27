import Combine
import CoreLocation
import Foundation
import Testing
@testable import TravelAssist

@Suite("Journey Plan Scheduling Tests")
struct JourneyPlanSchedulingTests {

    @Test("Adds multiple trips on same day and recomputes start + times")
    func testScheduleRecomputeChainsTripsWithinDay() async throws {
        let suiteName = "TravelAssistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = TripMonitoringRepositoryImpl(
            locationService: TestLocationService(),
            etaEstimator: TestETAEstimator(),
            alertService: TestFakeCallAlertService(),
            backgroundTaskScheduler: TestBackgroundTaskScheduler(),
            widgetSyncService: TestWidgetSyncService(),
            defaults: defaults
        )

        var latestItems: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latestItems = $0 }
        defer { cancellable.cancel() }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let trip1Start = dayStart.addingTimeInterval(9 * 3600)
        let trip2UserStart = trip1Start.addingTimeInterval(5 * 60)

        let trip1ID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let trip2ID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let trip1 = JourneyPlanItem(
            id: trip1ID,
            title: "Trip 1",
            subtitle: nil,
            latitude: 12.9716,
            longitude: 77.5946,
            userPlannedStartAt: trip1Start,
            plannedStartAt: trip1Start,
            estimatedTravelDurationSeconds: 10 * 60,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: trip1Start
        )

        let trip2 = JourneyPlanItem(
            id: trip2ID,
            title: "Trip 2",
            subtitle: nil,
            latitude: 12.9352,
            longitude: 77.6245,
            userPlannedStartAt: trip2UserStart,
            plannedStartAt: trip2UserStart,
            estimatedTravelDurationSeconds: 15 * 60,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: trip2UserStart
        )

        repository.addJourneyPlanItem(trip1)
        repository.addJourneyPlanItem(trip2)

        #expect(latestItems.count == 2)
        let updatedTrip1 = try #require(latestItems.first(where: { $0.id == trip1ID }))
        let updatedTrip2 = try #require(latestItems.first(where: { $0.id == trip2ID }))

        #expect(updatedTrip1.startLatitude == nil)
        #expect(updatedTrip1.startLongitude == nil)

        // Trip 2 should chain from Trip 1 end because user planned time overlaps.
        #expect(updatedTrip2.plannedStartAt == updatedTrip1.approximateEndAt)
        #expect(updatedTrip2.startLatitude == updatedTrip1.latitude)
        #expect(updatedTrip2.startLongitude == updatedTrip1.longitude)
        #expect(updatedTrip2.approximateEndAt == updatedTrip2.plannedStartAt.addingTimeInterval(15 * 60))
    }

    @Test("Completed items anchor later trip start and starting point")
    func testCompletedItemAnchorsNextTrip() async throws {
        let suiteName = "TravelAssistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = TripMonitoringRepositoryImpl(
            locationService: TestLocationService(),
            etaEstimator: TestETAEstimator(),
            alertService: TestFakeCallAlertService(),
            backgroundTaskScheduler: TestBackgroundTaskScheduler(),
            widgetSyncService: TestWidgetSyncService(),
            defaults: defaults
        )

        var latestItems: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latestItems = $0 }
        defer { cancellable.cancel() }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let completedStart = dayStart.addingTimeInterval(8 * 3600)
        let completedEnd = dayStart.addingTimeInterval(9 * 3600)
        let nextUserStart = dayStart.addingTimeInterval(8 * 3600 + 15 * 60)

        let completedID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let nextID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        let completed = JourneyPlanItem(
            id: completedID,
            title: "Completed",
            subtitle: nil,
            latitude: 3,
            longitude: 4,
            userPlannedStartAt: completedStart,
            plannedStartAt: completedStart,
            approximateEndAt: completedEnd,
            estimatedTravelDurationSeconds: 0,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            status: .completed,
            createdAt: completedStart
        )

        let next = JourneyPlanItem(
            id: nextID,
            title: "Next",
            subtitle: nil,
            latitude: 5,
            longitude: 6,
            userPlannedStartAt: nextUserStart,
            plannedStartAt: nextUserStart,
            estimatedTravelDurationSeconds: 60,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: nextUserStart
        )

        repository.addJourneyPlanItem(completed)
        repository.addJourneyPlanItem(next)

        let updatedNext = try #require(latestItems.first(where: { $0.id == nextID }))
        #expect(updatedNext.plannedStartAt == completedEnd)
        #expect(updatedNext.startLatitude == completed.latitude)
        #expect(updatedNext.startLongitude == completed.longitude)
    }

    @Test("Starting a trip earlier than planned shifts subsequent trips earlier when recalculating")
    func testEarlyStartChainsRemainingTripsEarlier() async throws {
        let suiteName = "TravelAssistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = TripMonitoringRepositoryImpl(
            locationService: TestLocationService(),
            etaEstimator: TestETAEstimator(),
            alertService: TestFakeCallAlertService(),
            backgroundTaskScheduler: TestBackgroundTaskScheduler(),
            widgetSyncService: TestWidgetSyncService(),
            defaults: defaults
        )

        var latestItems: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latestItems = $0 }
        defer { cancellable.cancel() }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

        let trip1Planned = dayStart.addingTimeInterval(9 * 3600)
        let trip1End = trip1Planned.addingTimeInterval(10 * 60)

        let trip2UserPlanned = dayStart.addingTimeInterval(12 * 3600)
        let trip3UserPlanned = dayStart.addingTimeInterval(13 * 3600)

        let trip1ID = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let trip2ID = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let trip3ID = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!

        let completedTrip1 = JourneyPlanItem(
            id: trip1ID,
            title: "Trip 1",
            subtitle: nil,
            latitude: 11,
            longitude: 12,
            userPlannedStartAt: trip1Planned,
            plannedStartAt: trip1Planned,
            approximateEndAt: trip1End,
            estimatedTravelDurationSeconds: 0,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .completed,
            createdAt: trip1Planned
        )

        let trip2 = JourneyPlanItem(
            id: trip2ID,
            title: "Trip 2",
            subtitle: nil,
            latitude: 21,
            longitude: 22,
            userPlannedStartAt: trip2UserPlanned,
            plannedStartAt: trip2UserPlanned,
            estimatedTravelDurationSeconds: 10 * 60,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: trip2UserPlanned
        )

        let trip3 = JourneyPlanItem(
            id: trip3ID,
            title: "Trip 3",
            subtitle: nil,
            latitude: 31,
            longitude: 32,
            userPlannedStartAt: trip3UserPlanned,
            plannedStartAt: trip3UserPlanned,
            estimatedTravelDurationSeconds: 10 * 60,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: trip3UserPlanned
        )

        repository.addJourneyPlanItem(completedTrip1)
        repository.addJourneyPlanItem(trip2)
        repository.addJourneyPlanItem(trip3)

        // With no actual deviation yet, planned times should remain at the user planned times.
        let baselineTrip2 = try #require(latestItems.first(where: { $0.id == trip2ID }))
        let baselineTrip3 = try #require(latestItems.first(where: { $0.id == trip3ID }))
        #expect(baselineTrip2.plannedStartAt == trip2UserPlanned)
        #expect(baselineTrip3.plannedStartAt == trip3UserPlanned)

        // User starts Trip 2 much earlier than planned; recompute should chain Trip 3 earlier too.
        let actualTrip2Start = dayStart.addingTimeInterval(9 * 3600 + 20 * 60)
        repository.start(
            session: TripSession(
                startCoordinate: CLLocationCoordinate2D(latitude: completedTrip1.latitude, longitude: completedTrip1.longitude),
                destinationCoordinate: CLLocationCoordinate2D(latitude: trip2.latitude, longitude: trip2.longitude),
                leadTimeMinutes: trip2.leadTimeMinutes,
                selectedJourneyMode: trip2.selectedJourneyMode,
                journeyPlanItemID: trip2ID,
                startedAt: actualTrip2Start
            )
        )

        let updatedTrip2 = try #require(latestItems.first(where: { $0.id == trip2ID }))
        let updatedTrip3 = try #require(latestItems.first(where: { $0.id == trip3ID }))
        #expect(updatedTrip2.plannedStartAt == actualTrip2Start)
        #expect(updatedTrip3.plannedStartAt == updatedTrip2.approximateEndAt)
    }

    @Test("Adding trips on different dates preserves all days")
    func testAddJourneyPlanItemDoesNotOverwriteOtherDays() async throws {
        let suiteName = "TravelAssistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = TripMonitoringRepositoryImpl(
            locationService: TestLocationService(),
            etaEstimator: TestETAEstimator(),
            alertService: TestFakeCallAlertService(),
            backgroundTaskScheduler: TestBackgroundTaskScheduler(),
            widgetSyncService: TestWidgetSyncService(),
            defaults: defaults
        )

        var latestItems: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latestItems = $0 }
        defer { cancellable.cancel() }

        let calendar = Calendar.current
        let day1 = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let day1Trip = JourneyPlanItem(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "Day 1",
            subtitle: nil,
            latitude: 1,
            longitude: 1,
            plannedStartAt: day1.addingTimeInterval(8 * 3600),
            estimatedTravelDurationSeconds: 60,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            createdAt: day1.addingTimeInterval(8 * 3600)
        )

        let day2Trip = JourneyPlanItem(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            title: "Day 2",
            subtitle: nil,
            latitude: 2,
            longitude: 2,
            plannedStartAt: day2.addingTimeInterval(8 * 3600),
            estimatedTravelDurationSeconds: 60,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            createdAt: day2.addingTimeInterval(8 * 3600)
        )

        repository.addJourneyPlanItem(day1Trip)
        repository.addJourneyPlanItem(day2Trip)

        #expect(latestItems.count == 2)
        #expect(latestItems.contains(where: { $0.id == day1Trip.id }))
        #expect(latestItems.contains(where: { $0.id == day2Trip.id }))
    }

    @Test("Duplicate protection removes near-identical trip additions")
    func testDuplicatePlanItemRemoval() async throws {
        let suiteName = "TravelAssistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = TripMonitoringRepositoryImpl(
            locationService: TestLocationService(),
            etaEstimator: TestETAEstimator(),
            alertService: TestFakeCallAlertService(),
            backgroundTaskScheduler: TestBackgroundTaskScheduler(),
            widgetSyncService: TestWidgetSyncService(),
            defaults: defaults
        )

        var latestItems: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latestItems = $0 }
        defer { cancellable.cancel() }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let plannedStart = dayStart.addingTimeInterval(10 * 3600)

        let firstID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let secondID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

        let first = JourneyPlanItem(
            id: firstID,
            title: "Trip",
            subtitle: nil,
            latitude: 10,
            longitude: 10,
            plannedStartAt: plannedStart,
            estimatedTravelDurationSeconds: 60,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            createdAt: plannedStart
        )

        let secondNearDuplicate = JourneyPlanItem(
            id: secondID,
            title: "Trip",
            subtitle: nil,
            latitude: 10,
            longitude: 10,
            plannedStartAt: plannedStart.addingTimeInterval(30),
            estimatedTravelDurationSeconds: 60,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5,
            createdAt: plannedStart.addingTimeInterval(30)
        )

        repository.addJourneyPlanItem(first)
        repository.addJourneyPlanItem(secondNearDuplicate)

        #expect(latestItems.count == 1)
        #expect(latestItems.first?.id == secondID)
    }

    @Test("JourneyPlanItem clamps negative durations to zero")
    func testJourneyPlanItemNegativeDurationClamped() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let item = JourneyPlanItem(
            title: "Trip",
            subtitle: nil,
            latitude: 0,
            longitude: 0,
            plannedStartAt: start,
            estimatedTravelDurationSeconds: -500,
            selectedJourneyMode: .walk,
            leadTimeMinutes: 5
        )

        #expect(item.estimatedTravelDurationSeconds == 0)
        #expect(item.approximateEndAt == start)
    }

    @Test("JourneyPlanItem decoding defaults missing duration using lead time floor")
    func testJourneyPlanItemDecodingDefaultsDuration() async throws {
        let json = """
        {
          "id": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
          "title": "Trip",
          "latitude": 1.0,
          "longitude": 2.0,
          "plannedStartAt": 0,
          "selectedJourneyMode": "walk",
          "leadTimeMinutes": 2,
          "status": "started",
          "createdAt": 0
        }
        """

        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let item = try decoder.decode(JourneyPlanItem.self, from: data)

        #expect(item.estimatedTravelDurationSeconds == 5 * 60)
        #expect(item.approximateEndAt == item.plannedStartAt.addingTimeInterval(5 * 60))
    }
}

private final class TestLocationService: LocationService {
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let authorizationSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.authorizedWhenInUse)

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus { authorizationSubject.value }
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { authorizationSubject.eraseToAnyPublisher() }
    var locationPublisher: AnyPublisher<CLLocation, Never> { locationSubject.eraseToAnyPublisher() }

    func requestPermissionsIfNeeded() {}
    func requestOneTimeLocation() {}
    func startStandardUpdates() {}
    func stopStandardUpdates() {}
    func startSignificantUpdates() {}
    func stopUpdates() {}
    func startMonitoringDestination(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) {}
    func stopMonitoringDestination() {}
}

private struct TestETAEstimator: ETAEstimator {
    func estimateETA(from currentLocation: CLLocation, to destination: CLLocationCoordinate2D, mode: JourneyMode) async -> ETAEstimate {
        ETAEstimate(distanceMeters: 1000, etaSeconds: 600)
    }
}

private struct TestFakeCallAlertService: FakeCallAlertService {
    func requestPermissionsIfNeeded() {}
    func scheduleFakeCall(in seconds: TimeInterval, message: String) {}
    func cancelPendingFakeCall() {}
}

private struct TestBackgroundTaskScheduler: BackgroundTaskScheduler {
    func register(refreshHandler: @escaping () -> Void) {}
    func scheduleRefresh() {}
}

private final class TestWidgetSyncService: WidgetSyncService {
    private(set) var lastSnapshot: TravelSnapshot?
    private(set) var lastSession: TripSession?
    private(set) var lastPlan: [JourneyPlanItem] = []

    func sync(snapshot: TravelSnapshot?, session: TripSession?) {
        lastSnapshot = snapshot
        lastSession = session
    }

    func syncJourneyPlan(_ items: [JourneyPlanItem]) {
        lastPlan = items
    }

    func clearActiveTrip() {
        lastSnapshot = nil
        lastSession = nil
    }
}
