import AVFoundation
import AudioToolbox
import CallKit
import Foundation
import UIKit
import UserNotifications
import MetricKit
import Speech

final class LocalFakeCallAlertService: NSObject, FakeCallAlertService {
    private let center = UNUserNotificationCenter.current()
    private let provider: CXProvider
    private let callController = CXCallController()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeCallUUID: UUID?
    private var pendingPromptMessage = AppConstants.fakeCallNotificationMessage
    private var scheduledCallWorkItem: DispatchWorkItem?
    private var shouldSpeakAfterActivation = false
    private var decisionContext: DecisionContext?
    private var decisionTimeoutWorkItem: DispatchWorkItem?

    private struct DecisionContext {
        let handler: (Bool) -> Void
        var hasDecided: Bool = false
    }

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
        decisionContext = nil
        decisionTimeoutWorkItem?.cancel()
        decisionTimeoutWorkItem = nil
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

    func scheduleDecisionFakeCall(
        in seconds: TimeInterval,
        message: String,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        pendingPromptMessage = normalizedPrompt(from: message)
        decisionContext = DecisionContext(handler: decisionHandler)
        decisionTimeoutWorkItem?.cancel()
        decisionTimeoutWorkItem = nil
        scheduledCallWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Always use CallKit for decision calls so BLE headset + side buttons work.
            self.reportIncomingFakeCall()
        }
        scheduledCallWorkItem = workItem

        requestSpeechPermissionsIfNeeded()

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
        decisionTimeoutWorkItem?.cancel()
        decisionTimeoutWorkItem = nil
        if let context = decisionContext, !context.hasDecided {
            // Treat cancellation as decline.
            decisionContext = nil
        }
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
            if decisionContext != nil {
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.allowBluetooth, .duckOthers, .defaultToSpeaker]
                )
            } else {
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
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

    private func requestSpeechPermissionsIfNeeded() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    private func finishDecision(_ result: Bool) {
        decisionTimeoutWorkItem?.cancel()
        decisionTimeoutWorkItem = nil

        stopListening()

        guard var context = decisionContext else {
            requestEndActiveCall()
            return
        }
        guard !context.hasDecided else {
            requestEndActiveCall()
            return
        }
        context.hasDecided = true
        decisionContext = context

        // Call handler then clear state.
        context.handler(result)
        decisionContext = nil

        requestEndActiveCall()
    }

    private func beginListeningForYesNo() {
        guard decisionContext != nil else {
            requestEndActiveCall()
            return
        }

        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            finishDecision(false)
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let text = result?.bestTranscription.formattedString.lowercased() {
                if text.contains("yes") || text.contains("yeah") || text.contains("yep") || text.contains("start") {
                    self.finishDecision(true)
                    return
                }
                if text.contains("no") || text.contains("don't") || text.contains("do not") || text.contains("stop") {
                    self.finishDecision(false)
                    return
                }
            }

            if error != nil {
                self.finishDecision(false)
            }
        }

        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.finishDecision(false)
        }
        decisionTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: timeoutItem)
    }

    private func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
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
        decisionTimeoutWorkItem?.cancel()
        decisionTimeoutWorkItem = nil
        stopListening()
        decisionContext = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        shouldSpeakAfterActivation = true
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        activeCallUUID = nil
        shouldSpeakAfterActivation = false
        if decisionContext != nil {
            // Treat hangup/power button/headset end as decline.
            finishDecision(false)
            // finishDecision will requestEndActiveCall, but we're already ending.
        } else {
            decisionTimeoutWorkItem?.cancel()
            decisionTimeoutWorkItem = nil
            stopListening()
            decisionContext = nil
        }
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
        if decisionContext != nil {
            beginListeningForYesNo()
        } else {
            requestEndActiveCall()
        }
    }
}
