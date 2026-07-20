import Foundation

/// The Drift Coach cloud brain (Nebius, team key from `AppConfig`): whether it's
/// provisioned, and how to make it `LocalAIService`'s active backend.
///
/// This is the top rung of the operator's standing AI ladder — Nebius first,
/// Google on-device intelligence next, the local parser/backend only as a last
/// resort — and it lives in DriftCore precisely so BOTH platforms climb the same
/// ladder. Falling back to a local parser on Android while iOS reaches the cloud
/// is a parity bug: the same utterance must get the same quality answer on both.
///
/// NOT user BYOK: no Keychain, no biometric prompt, no per-user key entry. The
/// iOS `AIBackendCoordinator` wraps this alongside its local-llama / Foundation
/// Models backends, which stay iOS-only.
@MainActor
public enum CoachCloud {

    /// True when the embedded team key decrypts. Callers that can degrade should
    /// check this rather than letting `install()` fail silently.
    public static var isConfigured: Bool { AppConfig.coachCloudConfigured }

    /// Install the coach cloud backend. Returns false when no team key is
    /// provisioned, so the caller falls back to on-device.
    @discardableResult
    public static func install() -> Bool {
        guard isConfigured else { return false }
        LocalAIService.shared.useRemoteBackend(
            provider: .nebius,
            modelID: AppConfig.coachModelID,
            apiKey: AppConfig.coachAPIKey
        )
        return true
    }
}
