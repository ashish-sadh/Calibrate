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

    /// Plays ElevenLabs MP3 audio (the cloud path). Held so `stop()` can halt it.
    @MainActor private var audioPlayer: AVAudioPlayer?
    /// Bumped on every `speak`/`stop` so a late-returning cloud synthesis can
    /// tell it's been superseded and bail instead of talking over a new turn.
    @MainActor private var playToken = 0

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

        // Supersede anything in flight (synth + cloud playback + pending fetch).
        playToken &+= 1
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        audioPlayer?.stop(); audioPlayer = nil
        self.onFinish = onFinish
        isSpeaking = true

        // Studio voice when an ElevenLabs key is provisioned; otherwise the best
        // on-device voice. The cloud path silently falls back on any failure.
        if AppConfig.elevenLabsConfigured {
            speakCloud(spoken, token: playToken)
        } else {
            speakOnDevice(spoken)
        }
    }

    /// On-device TTS via `AVSpeechSynthesizer` using the best installed voice.
    /// The free/private/instant path and the cloud path's fallback.
    @MainActor
    private func speakOnDevice(_ spoken: String) {
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

    /// Studio TTS via ElevenLabs: fetch MP3 off-main, then play. On ANY failure
    /// (network, key, decode) fall back to the on-device voice so the coach never
    /// goes silent. `token` guards against a stale result arriving after `stop()`
    /// or a newer turn.
    @MainActor
    private func speakCloud(_ spoken: String, token: Int) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await ElevenLabsTTSClient.synthesize(
                    text: spoken,
                    voiceID: AppConfig.coachVoiceID,
                    modelID: AppConfig.elevenLabsModelID,
                    apiKey: AppConfig.elevenLabsAPIKey)
                await MainActor.run { self.playCloudAudio(data, spoken: spoken, token: token) }
            } catch {
                Log.app.info("Coach voice: ElevenLabs failed (\(error)) — falling back on-device")
                await MainActor.run {
                    guard token == self.playToken else { return }
                    self.speakOnDevice(spoken)
                }
            }
        }
    }

    /// Play fetched MP3 bytes. If decoding fails, fall back on-device. Ignores a
    /// result the user already superseded.
    @MainActor
    private func playCloudAudio(_ data: Data, spoken: String, token: Int) {
        guard token == playToken else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            isSpeaking = true
            player.play()
        } catch {
            Log.app.info("Coach voice: ElevenLabs MP3 decode failed — falling back on-device")
            speakOnDevice(spoken)
        }
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
    /// Bumps the play token so any in-flight cloud synthesis is discarded.
    @MainActor
    func stop() {
        playToken &+= 1
        onFinish = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        audioPlayer?.stop(); audioPlayer = nil
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

// MARK: - AVAudioPlayerDelegate (ElevenLabs cloud path)

extension CoachVoiceService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
            let cb = self.onFinish; self.onFinish = nil
            cb?()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
            let cb = self.onFinish; self.onFinish = nil
            cb?()
        }
    }
}
