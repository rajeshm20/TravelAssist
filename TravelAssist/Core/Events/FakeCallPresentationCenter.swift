import Foundation

extension Notification.Name {
    static let fakeCallPresentationRequested = Notification.Name("travelassist.fakeCallPresentationRequested")
}

struct FakeCallPresentationRequest {
    let callerName: String
    let message: String

    fileprivate static let callerNameKey = "callerName"
    fileprivate static let messageKey = "message"

    static func from(userInfo: [AnyHashable: Any]?) -> FakeCallPresentationRequest? {
        guard let callerName = userInfo?[callerNameKey] as? String,
              let message = userInfo?[messageKey] as? String else {
            return nil
        }
        return FakeCallPresentationRequest(callerName: callerName, message: message)
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.callerNameKey: callerName,
            Self.messageKey: message
        ]
    }
}

enum FakeCallPresentationCenter {
    static func postIncomingCall(callerName: String = "Travel Assist", message: String) {
        let request = FakeCallPresentationRequest(callerName: callerName, message: message)
        NotificationCenter.default.post(
            name: .fakeCallPresentationRequested,
            object: nil,
            userInfo: request.userInfo
        )
    }
}
