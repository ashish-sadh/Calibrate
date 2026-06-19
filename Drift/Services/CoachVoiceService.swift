import Foundation
import AVFoundation
import DriftCore

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
        utterance.pitchMultiplier = 1.0
        utterance.voice = Self.preferredVoice
        utterance.prefersAssistiveTechnologySettings = false

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// The best-sounding installed English voice, chosen once. Apple's
    /// `AVSpeechSynthesisVoice(language:)` returns the *compact* (robotic) voice;
    /// the neural **premium** and **enhanced** voices sound dramatically more
    /// human but must be downloaded by the user (Settings → Accessibility →
    /// Spoken Content → Voices → English → tap a voice to download). We pick the
    /// highest-quality standard voice available, preferring en-US, and avoid the
    /// novelty voices (Zarvox, Bells, …). Falls back to the compact default when
    /// nothing better is installed. #coach-voice
    static let preferredVoice: AVSpeechSynthesisVoice? = {
        let fallback = AVSpeechSynthesisVoice(language: "en-US")
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return fallback }

        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium:    s += 100
            case .enhanced:   s += 50
            case .default:    s += 0
            @unknown default: s += 0
            }
            // Novelty voices (com.apple.speech.synthesis.voice.*) read badly —
            // hard-deprioritize so we never pick "Zarvox" over compact Samantha.
            if v.identifier.contains(".speech.synthesis.voice.") { s -= 200 }
            // Siri / neural voices sound the most natural when present.
            if v.identifier.lowercased().contains("siri") { s += 40 }
            // Prefer US English, then other major English locales.
            if v.language == "en-US" { s += 10 }
            else if ["en-GB", "en-AU", "en-IN", "en-IE"].contains(v.language) { s += 5 }
            return s
        }

        let best = english.max { score($0) < score($1) }
        if let best { Log.app.info("Coach voice: \(best.name) (\(best.language), quality \(best.quality.rawValue))") }
        return best ?? fallback
    }()

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
