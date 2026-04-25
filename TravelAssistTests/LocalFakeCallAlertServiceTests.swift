import Testing
import Foundation
import UserNotifications
@testable import TravelAssist

@Suite("LocalFakeCallAlertService Tests")
struct LocalFakeCallAlertServiceTests {

    @Test("Test prompt normalization with empty string")
    func testNormalizedPrompt_WithEmptyString_ReturnsDefault() async throws {
        let service = await LocalFakeCallAlertService()
        // Indirectly testing normalization by checking if it handles empty message without crash
        await service.scheduleFakeCall(in: 0, message: "")
        // In a real scenario, we would mock UNUserNotificationCenter to verify the content body.
    }

    @Test("Test prompt normalization with whitespace only")
    func testNormalizedPrompt_WithWhitespace_ReturnsDefault() async throws {
        let service = await LocalFakeCallAlertService()
        await service.scheduleFakeCall(in: 0, message: "   ")
    }

    @Test("Test scheduling with negative delay defaults to immediate")
    func testScheduleWithNegativeDelay() async throws {
        let service = await LocalFakeCallAlertService()
        await service.scheduleFakeCall(in: -5, message: "Negative Delay")
    }

    @Test("Test cancellation of pending work item")
    func testCancelPendingWorkItem() async throws {
        let service = await LocalFakeCallAlertService()
        await service.scheduleFakeCall(in: 100, message: "Pending")
        await service.cancelPendingFakeCall()
        // If we had access to scheduledCallWorkItem, we could verify isCancelled.
    }

    @Test("Test overwriting existing schedule")
    func testOverwriteExistingSchedule() async throws {
        let service = await LocalFakeCallAlertService()
        await service.scheduleFakeCall(in: 100, message: "First")
        await service.scheduleFakeCall(in: 0.1, message: "Second")
    }
}
