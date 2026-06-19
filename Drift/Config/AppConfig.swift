import Foundation
import CryptoKit

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
enum AppConfig {

    /// Nebius model powering the coach. Qwen3-235B-Instruct — fast (~1s),
    /// concise, grounded, good tool-calling. Deliberately an *instruct* model,
    /// not a reasoning model (Kimi K2.6/R1 burn the token budget thinking and
    /// never finish a short spoken reply).
    static let coachModelID = "Qwen/Qwen3-235B-A22B-Instruct-2507"

    /// Vision model for image turns — the text coach model can't see images
    /// (400s). Verified to accept image_url on Nebius. #coach-agent-loop
    static let coachVisionModelID = "Qwen/Qwen2.5-VL-72B-Instruct"

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
    static var coachAPIKey: String {
        guard !coachKeyCiphertextB64.isEmpty,
              let data = Data(base64Encoded: coachKeyCiphertextB64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: unlockKey),
              let key = String(data: plain, encoding: .utf8) else { return "" }
        return key
    }

    /// True when the embedded key decrypts — the cloud coach is selectable.
    static var coachCloudConfigured: Bool { !coachAPIKey.isEmpty }
}
