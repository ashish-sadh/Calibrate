import Foundation
@testable import DriftCore
import Testing

// ElevenLabs TTS request builder + guard rails. Pure (no network). #coach-voice

@Test func buildRequestHasCorrectURLAndQuery() throws {
    let req = try #require(ElevenLabsTTSClient.buildRequest(
        text: "hello", voiceID: "VID123", modelID: "eleven_turbo_v2_5", apiKey: "k"))
    let url = try #require(req.url)
    #expect(url.host == "api.elevenlabs.io")
    #expect(url.path.hasSuffix("/v1/text-to-speech/VID123"))
    #expect(url.absoluteString.contains("output_format=mp3_44100_128"))
}

@Test func buildRequestHasAuthAndContentHeaders() throws {
    let req = try #require(ElevenLabsTTSClient.buildRequest(
        text: "hello", voiceID: "v", modelID: "m", apiKey: "secret-key"))
    #expect(req.httpMethod == "POST")
    #expect(req.value(forHTTPHeaderField: "xi-api-key") == "secret-key")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(req.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
}

@Test func buildRequestBodyCarriesTextModelAndSettings() throws {
    let req = try #require(ElevenLabsTTSClient.buildRequest(
        text: "log my lunch", voiceID: "v", modelID: "eleven_turbo_v2_5", apiKey: "k"))
    let body = try #require(req.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["text"] as? String == "log my lunch")
    #expect(json["model_id"] as? String == "eleven_turbo_v2_5")
    let settings = try #require(json["voice_settings"] as? [String: Any])
    #expect(settings["stability"] != nil)
    #expect(settings["similarity_boost"] != nil)
    #expect(settings["use_speaker_boost"] as? Bool == true)
}

@Test func synthesizeRejectsEmptyText() async {
    await #expect(throws: ElevenLabsTTSClient.TTSError.emptyText) {
        try await ElevenLabsTTSClient.synthesize(
            text: "   ", voiceID: "v", modelID: "m", apiKey: "k")
    }
}

@Test func synthesizeRejectsMissingKey() async {
    await #expect(throws: ElevenLabsTTSClient.TTSError.missingKey) {
        try await ElevenLabsTTSClient.synthesize(
            text: "hello", voiceID: "v", modelID: "m", apiKey: "")
    }
}
