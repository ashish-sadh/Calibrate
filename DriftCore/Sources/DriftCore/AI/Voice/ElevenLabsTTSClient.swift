import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cloud text-to-speech via ElevenLabs — the coach's studio voice.
///
/// Pure-ish: `buildRequest` is a deterministic function of its inputs (Tier-0
/// testable); `synthesize` does the actual network fetch and returns the raw
/// MP3 bytes. Playback lives on the iOS side (`CoachVoiceService`), which falls
/// back to the on-device `AVSpeechSynthesizer` voice on any failure here.
///
/// Privacy note: this sends the coach's reply *text* to ElevenLabs — a cloud
/// touchpoint, surfaced to the user. The listening (speech-in) stays on-device.
public enum ElevenLabsTTSClient {

    /// Output format requested from ElevenLabs. MP3 plays directly via
    /// `AVAudioPlayer`; 44.1kHz/128kbps is the natural-quality default.
    public static let outputFormat = "mp3_44100_128"

    /// Tuning for the synthesized voice. Mid stability keeps it expressive but
    /// not erratic; speaker boost adds presence. Defaults suit a warm coach.
    public struct VoiceSettings: Sendable {
        public var stability: Double
        public var similarityBoost: Double
        public var style: Double
        public var useSpeakerBoost: Bool
        public init(stability: Double = 0.5,
                    similarityBoost: Double = 0.75,
                    style: Double = 0.0,
                    useSpeakerBoost: Bool = true) {
            self.stability = stability
            self.similarityBoost = similarityBoost
            self.style = style
            self.useSpeakerBoost = useSpeakerBoost
        }
        public static let coach = VoiceSettings()
    }

    public enum TTSError: Error, Equatable {
        case emptyText
        case missingKey
        case badStatus(Int)
        case emptyAudio
    }

    /// Build the POST request for a synthesis call. Deterministic — no I/O — so
    /// it can be asserted in Tier-0 (URL, headers, body shape). Returns nil only
    /// for an unconstructable URL (never in practice with a real voice ID).
    public static func buildRequest(text: String,
                                    voiceID: String,
                                    modelID: String,
                                    apiKey: String,
                                    settings: VoiceSettings = .coach) -> URLRequest? {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")
        components?.queryItems = [URLQueryItem(name: "output_format", value: outputFormat)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": settings.stability,
                "similarity_boost": settings.similarityBoost,
                "style": settings.style,
                "use_speaker_boost": settings.useSpeakerBoost,
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Fetch synthesized MP3 audio for `text`. Throws `TTSError` on empty input,
    /// missing key, non-2xx status, or empty audio — the caller falls back to
    /// the on-device voice.
    public static func synthesize(text: String,
                                  voiceID: String,
                                  modelID: String,
                                  apiKey: String,
                                  settings: VoiceSettings = .coach,
                                  session: URLSession = .shared) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }
        guard !apiKey.isEmpty else { throw TTSError.missingKey }
        guard let request = buildRequest(text: trimmed, voiceID: voiceID,
                                         modelID: modelID, apiKey: apiKey,
                                         settings: settings) else {
            throw TTSError.badStatus(-1)
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TTSError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw TTSError.emptyAudio }
        return data
    }
}
