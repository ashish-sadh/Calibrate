import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Build-time configuration for Drift Coach's cloud brain.
///
/// Drift Coach runs on Nebius AI Studio (OpenAI-compatible) using a single
/// **team key**, not user BYOK. The key is NOT shipped in plaintext: only an
/// AES-GCM ciphertext is embedded below, and the unlock key is reconstructed at
/// runtime from scattered constants — so a `strings`/bundle dump won't surface
/// the key.
///
/// ⚠️ This is **obfuscation, not security.** A secret that the app can decrypt
/// at runtime can always be recovered from a running app (memory dump, hooking
/// the decrypt). It defeats casual scraping only. It is paired with a hard
/// spending cap on the Nebius key so an extracted key is low-stakes; rotate the
/// key after the hackathon. The real fix (a serverless proxy holding the key) is
/// the post-hackathon path.
///
/// To rotate / re-key: AES-GCM-seal the new key with the SAME derivation as
/// `unlockKey` below (a one-off `swift` script using CryptoKit), base64 the
/// `sealedBox.combined`, and replace `coachKeyCiphertextB64`.
///
/// Lives in DriftCore (not the iOS app) so Android reaches the same cloud brain
/// with the same key — the operator's standing AI ladder is Nebius first, local
/// only as the last resort, on BOTH platforms (#1064). Off-Apple the `Crypto`
/// module above is swift-crypto, which is API-identical for the AES-GCM +
/// SHA-256 used here, so there is one code path.
public enum AppConfig {

    /// Nebius model powering the coach. Qwen3-235B-Instruct — fast (~1s),
    /// concise, grounded, good tool-calling. Deliberately an *instruct* model,
    /// not a reasoning model (Kimi K2.6/R1 burn the token budget thinking and
    /// never finish a short spoken reply).
    static let coachModelID = "Qwen/Qwen3-235B-A22B-Instruct-2507"

    /// Vision model for image turns — the text coach model can't see images
    /// (400s). Verified to accept image_url on Nebius. #coach-agent-loop
    public static let coachVisionModelID = "Qwen/Qwen2.5-VL-72B-Instruct"

    /// The Nebius provider the coach installs. Base URL is encoded in
    /// `RemoteLLMBackend.Provider.nebius`.
    static let coachProvider = "nebius"

    /// AES-GCM(combined: nonce‖ciphertext‖tag) of the team Nebius key, base64.
    /// Only the ciphertext ships; see `unlockKey` for how it's opened.
    private static let coachKeyCiphertextB64 =
        "Upzhzx7t932rG7agnXFDR3kkp1Hs6eClltEzIVlzNYuLmT0eVhucr/DQexhoDApXL+qzL0v0AejHZmNbC74du7LF0EbIryvAqQtpAS4ZSbsYvrZiK5Up6lfYGCyz3WTEcXnoF39SuJ8PQ3zBn+MIBDR+Qzka1FKxQj5pqNW2kkyYDo7o1fLW15vQqai0C7yoHWTKD+NyzfbIu1w9f6k/5ZRhPPj6TTDdc1ldQhIfYUKNPv7rPw4D2kiFLdFk2rPdjndUamAbkf2vl/mfmdaoN9+rFyP3LJ9488Yeg2ds+1dUOnUdPKj8JXEKk1IzrBSt1f2jM2veaKuQ9LqSrvci9q7LZZuGExA="

    /// Reconstruct the AES-256 unlock key — derived (SHA-256) from scattered
    /// pieces, never stored as a literal. MUST match the offline seal script.
    private static var unlockKey: SymmetricKey {
        let parts = ["dr1ft", "c0ach", "n3b", "com.drift.health"]
        let material = parts.joined(separator: "\u{00B7}")
        return SymmetricKey(data: SHA256.hash(data: Data(material.utf8)))
    }

    /// Decrypt the team Nebius key from the embedded ciphertext. Returns "" if
    /// the ciphertext is absent/garbled — `coachCloudConfigured` then reads
    /// false and the coach degrades to on-device.
    ///
    /// Deliberately a computed `var`, not a stored `let`: it must NOT decrypt
    /// during module init, which would put an AES open on every cold start.
    static var coachAPIKey: String {
        guard !coachKeyCiphertextB64.isEmpty,
              let data = Data(base64Encoded: coachKeyCiphertextB64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: unlockKey),
              let key = String(data: plain, encoding: .utf8) else { return "" }
        return key
    }

    /// True when the embedded key decrypts — the cloud coach is selectable.
    public static var coachCloudConfigured: Bool { !coachAPIKey.isEmpty }

    // MARK: - ElevenLabs cloud TTS (studio coach voice)

    /// ElevenLabs voice ID for the coach. "Rachel" — calm, warm, reliable.
    /// Swap for any voice ID from the ElevenLabs library.
    public static let coachVoiceID = "21m00Tcm4TlvDq8ikWAM"

    /// ElevenLabs model. `eleven_turbo_v2_5` — low latency (~300ms) with quality
    /// close to multilingual_v2; right balance for a real-time spoken coach.
    public static let elevenLabsModelID = "eleven_turbo_v2_5"

    /// AES-GCM(combined) of the ElevenLabs API key, base64 — sealed with the
    /// SAME `unlockKey` derivation as the Nebius key. Only ciphertext ships.
    /// Same caveat as `coachKeyCiphertextB64`: obfuscation, not security; the
    /// key is on a spending cap and should be rotated after the hackathon.
    private static let elevenLabsKeyCiphertextB64 =
        "mJ/nOI/v3fCnaQBZ/n+vrbZRMYhLBI3qW/wQNCpZoIRTiQz/rEKeKgxIrqtQDvr+x56B8Im6z3IA1Zb61BS2QbT+byi+mrHAgb9Cq0mAfQ=="

    /// Decrypt the ElevenLabs key. Returns "" when absent/garbled — the coach
    /// then falls back to the on-device voice.
    public static var elevenLabsAPIKey: String {
        guard !elevenLabsKeyCiphertextB64.isEmpty,
              let data = Data(base64Encoded: elevenLabsKeyCiphertextB64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: unlockKey),
              let key = String(data: plain, encoding: .utf8) else { return "" }
        return key
    }

    /// True when the ElevenLabs key decrypts — studio voice is available.
    public static var elevenLabsConfigured: Bool { !elevenLabsAPIKey.isEmpty }

    // MARK: - Friends & Trainer sharing (Supabase)

    /// Base URL of the Drift sharing backend (Supabase project). REST lives at
    /// `<base>/rest/v1`, auth at `<base>/auth/v1`, realtime at `<base>/realtime/v1`.
    /// Hardcoded like `RemoteLLMBackend.Provider.nebius` — one project serves
    /// iOS + Android. Sharing is strictly opt-in; nothing here is touched until
    /// the user claims a username.
    public static let syncBaseURL = "https://ldyapxvnhlyqqfefqijj.supabase.co"

    /// Supabase **publishable** (anon) key. Public-safe by design: it grants
    /// only what Row-Level Security allows for the authenticated caller, so it
    /// ships in plaintext (unlike the Nebius team key). Sent as the `apikey`
    /// header on every sharing request.
    public static let syncAnonKey = "sb_publishable_650DZylHW7JZx3bsW4toPg_Cz7bY8Iq"

    /// True when a sharing backend is configured — gates the whole feature.
    public static var syncConfigured: Bool {
        !syncBaseURL.isEmpty && !syncAnonKey.isEmpty
    }
}
