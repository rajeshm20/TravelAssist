import SwiftUI
import AVFoundation
import AudioToolbox
import Combine

struct NextTripVoicePromptView: View {
    let tripTitle: String
    let onStart: () -> Void
    let onNotNow: () -> Void

    @StateObject private var listener = VoiceConfirmationListener()
    @StateObject private var speaker = SpokenPromptSpeaker()
    @State private var didRequestPermissions = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 0.19, green: 0.45, blue: 0.93))

                Text("Start next trip?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(tripTitle)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if listener.isListening {
                    Text("Say “yes” to start, or “no” to skip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap Start to begin, or Not now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                        onNotNow()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                        onStart()
                    } label: {
                        Text("Start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .navigationTitle("Next Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        onNotNow()
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            speakPromptIfNeeded()
            startListeningIfPossible()
        }
        .onDisappear {
            listener.stop()
            speaker.stop()
        }
    }

    private func speakPromptIfNeeded() {
        speaker.speak("Start next trip to \(tripTitle) now?") {}
    }

    private func startListeningIfPossible() {
        guard !didRequestPermissions else { return }
        didRequestPermissions = true

        Task { @MainActor in
            let allowed = await listener.requestPermissions()
            guard allowed else { return }
            listener.start(timeoutSeconds: 10) { result in
                switch result {
                case .yes:
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    onStart()
                case .no:
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    onNotNow()
                }
            }
        }
    }
}

@MainActor
private final class SpokenPromptSpeaker: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Best-effort.
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.volume = 1.0
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let finished = completion
            completion = nil
            finished?()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
