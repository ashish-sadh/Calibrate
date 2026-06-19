import Foundation

/// Build-time configuration for Drift Coach's cloud brain.
///
/// Drift Coach runs on Nebius AI Studio (OpenAI-compatible) using a single
/// **team key**, not user BYOK (#coach-rework). The key is loaded from a
/// git-ignored bundled resource (`Drift/Resources/nebius.key`) so it ships in
/// the app for the hackathon demo but never enters version control. When the
/// key is absent the coach degrades gracefully to the on-device backend.
///
/// Production path (post-hackathon): replace this with a central server that
/// holds the key + HydraDB session context, so no key ships in the client.
enum AppConfig {

    /// Nebius model powering the coach. Qwen3-235B-Instruct — fast (~1s),
    /// concise, grounded, good tool-calling. Deliberately an *instruct* model,
    /// not a reasoning model (Kimi K2.6/R1 burn the token budget thinking and
    /// never finish a short spoken reply).
    static let coachModelID = "Qwen/Qwen3-235B-A22B-Instruct-2507"

    /// The Nebius provider the coach installs. Base URL is encoded in
    /// `RemoteLLMBackend.Provider.nebius`.
    static let coachProvider = "nebius"

    /// Team Nebius API key, loaded from the git-ignored `nebius.key` resource.
    /// Empty when not provisioned — `coachCloudConfigured` is the gate callers
    /// check before offering the cloud coach.
    static var coachAPIKey: String {
        guard let url = Bundle.main.url(forResource: "nebius", withExtension: "key"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a team key is bundled — the cloud coach is selectable.
    static var coachCloudConfigured: Bool { !coachAPIKey.isEmpty }
}
