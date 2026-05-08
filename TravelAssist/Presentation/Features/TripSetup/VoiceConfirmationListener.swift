import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceConfirmationListener: ObservableObject {
    enum Result {
        case yes
        case no
    }

    @Published var isListening: Bool = false

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var isTapInstalled = false

    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else { return false }

        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        return micAllowed
    }

    func start(
        timeoutSeconds: TimeInterval = 10,
        onResult: @escaping (Result) -> Void
    ) {
        stop()
        guard recognizer?.isAvailable == true else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            // Best-effort; if we can't configure audio session, don't crash the app.
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = ["yes", "no", "start", "not now", "cancel", "ok", "okay"]
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        isTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            return
        }

        isListening = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString.lowercased()
            if text.contains("yes") || text.contains("start") || text.contains("ok") || text.contains("okay") {
                Task { @MainActor in
                    onResult(.yes)
                    self?.stop()
                }
            } else if text.contains("no") || text.contains("not now") || text.contains("cancel") {
                Task { @MainActor in
                    onResult(.no)
                    self?.stop()
                }
            }
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            self?.stop()
        }
    }

    func stop() {
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine.stop()
        audioEngine.reset()
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
