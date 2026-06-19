import Foundation
import AVFoundation

/// On-device text-to-speech for Drift Coach's voice talk-mode (#coach-rework).
///
/// Speaks the coach's replies aloud via `AVSpeechSynthesizer` — free, on-device,
/// no network, no permission prompt. Pairs with `SpeechRecognitionService` (voice
/// IN): together they make the coach a back-and-forth voice surface where the user
/// talks and the coach talks back while cards render on screen. Only the LLM turn
/// (text → text) leaves the device; the listening and speaking stay local.
///
/// Audio-session coordination: `SpeechRecognitionService` owns the session while
/// recording (`.playAndRecord / .measurement`). TTS sets a spoken-playback
/// category just before speaking, so the two never fight — callers stop recording
/// before they speak, and stop speaking before they record.
@Observable
final class CoachVoiceService: NSObject, @unchecked Sendable {
    static let shared = CoachVoiceService()

    /// True while an utterance is being spoken — drives the input-bar stop/anim.
    @MainActor private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (@MainActor () -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text` aloud. Strips markdown so the synthesizer doesn't read
    /// asterisks/hashes. `onFinish` fires on the main actor when speech ends or
    /// is cancelled — used by talk-mode to optionally re-open the mic. A blank
    /// string is a no-op that still calls `onFinish` (keeps a loop progressing).
    @MainActor
    func speak(_ text: String, onFinish: (@MainActor () -> Void)? = nil) {
        let spoken = Self.plainSpeech(text)
        guard !spoken.isEmpty else { onFinish?(); return }

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        self.onFinish = onFinish

        // Spoken-audio playback; duck (not interrupt) any other audio.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.prefersAssistiveTechnologySettings = false

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately (user tapped stop, or started recording).
    @MainActor
    func stop() {
        onFinish = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    /// Strip markdown emphasis / headings / code fences / link syntax so the
    /// voice reads natural prose, and collapse whitespace. Pure + cheap.
    static func plainSpeech(_ text: String) -> String {
        var s = text
        // Code fences and inline code backticks.
        s = s.replacingOccurrences(of: "```", with: " ")
        s = s.replacingOccurrences(of: "`", with: "")
        // Markdown link [label](url) -> label.
        if let re = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }
        // Emphasis / heading / list markers.
        for token in ["**", "__", "*", "_", "#", ">"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        // Collapse runs of whitespace/newlines.
        if let re = try? NSRegularExpression(pattern: #"\s+"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension CoachVoiceService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            let cb = self.onFinish; self.onFinish = nil
            cb?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinish = nil
        }
    }
}
