import Foundation

final class FakeCallDecisionCenter {
    static let shared = FakeCallDecisionCenter()

    private let lock = NSLock()
    private var handler: ((Bool) -> Void)?

    private init() {}

    func arm(handler: @escaping (Bool) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func clear() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func handleNotificationAction(_ actionIdentifier: String) {
        let resolved: Bool?
        switch actionIdentifier {
        case AppConstants.fakeCallDecisionActionStartID:
            resolved = true
        case AppConstants.fakeCallDecisionActionSkipID:
            resolved = false
        default:
            resolved = nil
        }
        guard let resolved else { return }

        lock.lock()
        let captured = handler
        handler = nil
        lock.unlock()

        captured?(resolved)
    }
}

