import Foundation

protocol FakeCallAlertService {
    func requestPermissionsIfNeeded()
    func scheduleFakeCall(in seconds: TimeInterval, message: String)
    func scheduleDecisionFakeCall(
        in seconds: TimeInterval,
        message: String,
        decisionHandler: @escaping (Bool) -> Void
    )
    func cancelPendingFakeCall()
}
