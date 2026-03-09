import Foundation

protocol FakeCallAlertService {
    func requestPermissionsIfNeeded()
    func scheduleFakeCall(in seconds: TimeInterval, message: String)
    func cancelPendingFakeCall()
}

