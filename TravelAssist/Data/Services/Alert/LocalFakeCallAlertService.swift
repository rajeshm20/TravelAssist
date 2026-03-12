import AVFoundation
import AudioToolbox
import CallKit
import Foundation
import UIKit
import UserNotifications

final class LocalFakeCallAlertService: NSObject, FakeCallAlertService {
    private let center = UNUserNotificationCenter.current()
    private let provider: CXProvider
    private let callController = CXCallController()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var activeCallUUID: UUID?
    private var pendingPromptMessage = AppConstants.fakeCallNotificationMessage
    private var scheduledCallWorkItem: DispatchWorkItem?
    private var shouldSpeakAfterActivation = false

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "Travel Assist")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        configuration.iconTemplateImageData = nil

        self.provider = CXProvider(configuration: configuration)
        super.init()

        provider.setDelegate(self, queue: .main)
        speechSynthesizer.delegate = self
    }

    func requestPermissionsIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleFakeCall(in seconds: TimeInterval, message: String) {
        pendingPromptMessage = normalizedPrompt(from: message)
        scheduledCallWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.presentInAppCallIfActive() {
                return
            }
            self.reportIncomingFakeCall()
        }
        scheduledCallWorkItem = workItem

        if seconds <= 0 {
            if Thread.isMainThread {
                workItem.perform()
            } else {
                DispatchQueue.main.sync {
                    workItem.perform()
                }
            }
            if scheduledCallWorkItem === workItem {
                scheduledCallWorkItem = nil
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    func cancelPendingFakeCall() {
        center.removePendingNotificationRequests(withIdentifiers: [AppConstants.fakeCallNotificationID])
        scheduledCallWorkItem?.cancel()
        scheduledCallWorkItem = nil
    }

    private func reportIncomingFakeCall() {
        let callUUID = UUID()
        activeCallUUID = callUUID

        let update = CXCallUpdate()
        update.localizedCallerName = "Travel Assist"
        update.remoteHandle = CXHandle(type: .generic, value: "Travel Assist")
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        update.hasVideo = false

        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.reportFallbackNotification()
                return
            }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func presentInAppCallIfActive() -> Bool {
        guard UIApplication.shared.applicationState == .active else {
            return false
        }

        FakeCallPresentationCenter.postIncomingCall(
            callerName: "Travel Assist",
            message: pendingPromptMessage
        )
        return true
    }

    private func normalizedPrompt(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AppConstants.fakeCallNotificationMessage
        }
        return trimmed
    }

    private func speakPromptAfterAnswer() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            // Use default audio route if session config fails.
        }

        let utterance = AVSpeechUtterance(string: pendingPromptMessage)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }

    private func requestEndActiveCall() {
        guard let activeCallUUID else { return }
        let endAction = CXEndCallAction(call: activeCallUUID)
        let transaction = CXTransaction(action: endAction)
        callController.request(transaction) { _ in }
    }

    private func reportFallbackNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Travel Assist Calling"
        content.body = pendingPromptMessage
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: AppConstants.fakeCallNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}

extension LocalFakeCallAlertService: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        shouldSpeakAfterActivation = true
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        activeCallUUID = nil
        shouldSpeakAfterActivation = false
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        guard shouldSpeakAfterActivation else { return }
        shouldSpeakAfterActivation = false
        speakPromptAfterAnswer()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // No-op
    }
}

extension LocalFakeCallAlertService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        requestEndActiveCall()
    }
}
