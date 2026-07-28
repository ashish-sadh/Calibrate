#if !DRIFT_IOS_APP
import Foundation

// No-op stand-ins for the iOS-only speech-input + TTS services, so the shared
// Coach ViewModel and View compile unchanged wherever the real services are
// absent. Voice talk-mode is gated off on Android v1 (#1066); the real Android
// SpeechRecognizer + TextToSpeech seam replaces these in #1126.
//
// Guarded on `!DRIFT_IOS_APP` (NOT `os(Android)`): the shared VM references
// these UNGATED, so they must exist in BOTH the Skip Android pass AND the Skip
// Darwin bridging pass (macOS, os(Android)=false) — only the real iOS app
// target (DRIFT_IOS_APP) has the actual services ([Skip SharedUI Three Configs]).

@MainActor
final class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()

    enum RecordingState: Equatable {
        case idle
        case recording
        case unavailable(String)
    }

    let recordingState: RecordingState = .idle
    let isRecording: Bool = false
    let transcript: String = ""

    func toggleRecording(onTranscript: (String) -> Void,
                         onDone: (String) -> Void,
                         endpointSilence: TimeInterval) {}
    func forceStop() {}
    func gracefulStop() {}
}

@MainActor
final class CoachVoiceService {
    static let shared = CoachVoiceService()

    let isSpeaking: Bool = false

    func speak(_ text: String) {}
    func speak(_ text: String, completion: () -> Void) { completion() }
    func stop() {}
}
#endif
