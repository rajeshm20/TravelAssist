import Combine
import CoreLocation
import Foundation
import Testing
@testable import TravelAssist

@Suite("iCloud Journey Plan Sync Tests")
struct ICloudJourneyPlanSyncTests {

    @Test("Remote newer updatedAt wins on merge")
    func testMergePrefersRemoteWhenNewer() async throws {
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

        var latest: [JourneyPlanItem] = []
        let cancellable = repository.journeyPlanPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let local = JourneyPlanItem(
            id: itemID,
            title: "Local",
            subtitle: nil,
            latitude: 1,
            longitude: 2,
            userPlannedStartAt: t0,
            plannedStartAt: t0,
            estimatedTravelDurationSeconds: 600,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: t0,
            updatedAt: t0
        )

        let remote = JourneyPlanItem(
            id: itemID,
            title: "Remote",
            subtitle: nil,
            latitude: 1,
            longitude: 2,
            userPlannedStartAt: t0,
            plannedStartAt: t0,
            estimatedTravelDurationSeconds: 600,
            selectedJourneyMode: .car,
            leadTimeMinutes: 5,
            status: .started,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(60)
        )

        repository.addJourneyPlanItem(local)
        #expect(latest.first?.title == "Local")

        repository.mergeJourneyPlanFromICloud([remote])
        #expect(latest.count == 1)
        #expect(latest.first?.title == "Remote")
    }
}

private final class TestLocationService: LocationService {
    var currentLocation: CLLocation? = nil
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { Just(authorizationStatus).eraseToAnyPublisher() }
    var locationPublisher: AnyPublisher<CLLocation, Never> { Empty().eraseToAnyPublisher() }
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
        ETAEstimate(distanceMeters: 0, etaSeconds: 0)
    }
}

private struct TestFakeCallAlertService: FakeCallAlertService {
    func requestPermissionsIfNeeded() {}
    func scheduleFakeCall(in seconds: TimeInterval, message: String) {}
    func scheduleDecisionFakeCall(in seconds: TimeInterval, message: String, decisionHandler: @escaping (Bool) -> Void) {}
    func cancelPendingFakeCall() {}
}

private struct TestBackgroundTaskScheduler: BackgroundTaskScheduler {
    func register(refreshHandler: @escaping () -> Void) {}
    func scheduleRefresh() {}
}

private final class TestWidgetSyncService: WidgetSyncService {
    func sync(snapshot: TravelSnapshot?, session: TripSession?) {}
    func syncJourneyPlan(_ plan: [JourneyPlanItem]) {}
    func clearActiveTrip() {}
}
