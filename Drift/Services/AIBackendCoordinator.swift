import Foundation
import DriftCore

/// iOS-side wiring for swapping `LocalAIService`'s active backend between
/// local llama.cpp and remote BYOK (Anthropic / OpenAI / Gemini). Handles
/// the Keychain unlock for the remote path; DriftCore itself never touches
/// Keychain. #515.
///
/// Single place to ask: "given the user's preference + what's actually
/// available right now, what should the chat service be using?"
@MainActor
enum AIBackendCoordinator {

    /// Whether the Drift Coach cloud brain (Nebius, team key from `AppConfig`)
    /// is provisioned. The chat/coach path no longer uses a user-entered BYOK
    /// key — that path is archived (see `Drift/Archive/`). Photo Log keeps its
    /// own Keychain BYOK, untouched.
    ///
    /// The cloud rung itself now lives in DriftCore (`CoachCloud`) so Android
    /// reaches the same brain; this stays as the iOS-side name the rest of the
    /// app already asks.
    static var hasCoachCloud: Bool {
        CoachCloud.isConfigured
    }

    /// Whether the local Drift brain has been downloaded.
    static var hasLocalBrain: Bool {
        AIModelManager.shared.isModelDownloaded
    }

    /// Whether Apple Foundation Models is available right now (iOS 26+,
    /// Apple-Intelligence-eligible hardware, AI enabled in Settings).
    /// Read by `applyPreferredBackend` to decide whether `.foundationModels`
    /// is a reachable choice; also by the chat empty-state to decide
    /// whether to offer "Use Apple Intelligence" as a setup option.
    static var hasFoundationModels: Bool {
        FoundationModelsBackend.isAvailableNow
    }

    /// Whether BOTH backends are available — the in-chat cpu/cloud toggle
    /// only renders when this is true. With only one backend the toggle
    /// would be a no-op and just clutter the input bar.
    static var bothBackendsAvailable: Bool {
        hasCoachCloud && hasLocalBrain
    }

    /// At least one backend can serve a chat turn. Drives the empty-state
    /// chooser CTA — when this is false, the chat shows the side-by-side
    /// "Cloud AI vs On-device" cards instead of the input bar.
    static var anyBackendAvailable: Bool {
        hasCoachCloud || hasLocalBrain
    }

    /// Apply the user's preferred backend to `LocalAIService`. Returns true
    /// when the requested backend was installed; false when prerequisites
    /// (key / model) are missing — caller can fall back to whichever
    /// backend IS available, or surface the empty-state chooser.
    /// Triggers a Keychain biometric prompt for the remote path.
    @discardableResult
    static func applyPreferredBackend() async -> Bool {
        switch Preferences.preferredAIBackend {
        case .remote:
            return installCoachBackend()
        case .llamaCpp, .mlx:
            return installLocalBackend()
        case .foundationModels:
            return installFoundationModelsBackend()
        }
    }

    /// Install the Drift Coach cloud backend — Nebius (OpenAI-compatible) with
    /// the team key from `AppConfig`. NOT user BYOK: no Keychain, no biometric
    /// prompt, no per-user key entry. Returns false when no team key is
    /// provisioned, so the caller falls back to on-device.
    ///
    /// (The old BYOK chat path — `installRemoteBackend` reading the Photo Log
    /// Keychain entry — is archived in `Drift/Archive/`, preserved but excluded
    /// from the build. Photo Log itself still uses BYOK via its own path.)
    @discardableResult
    static func installCoachBackend() -> Bool {
        CoachCloud.install()
    }

    /// Install the local backend: clears any in-place remote, then triggers
    /// the lazy load. Returns false when no model is downloaded (caller
    /// should redirect to the AI setup flow). Synchronous because the
    /// actual model load happens on a background task inside
    /// `LocalAIService.loadModel()`.
    @discardableResult
    static func installLocalBackend() -> Bool {
        let svc = LocalAIService.shared
        if svc.activeBackendType == .remote {
            svc.clearRemoteBackend()
        }
        if svc.activeBackendType == .foundationModels {
            svc.clearFoundationModelsBackend()
        }
        guard hasLocalBrain else { return false }
        if !svc.isModelLoaded { svc.loadModel() }
        return true
    }

    /// Install the Apple Foundation Models backend. Returns false when FM
    /// is unavailable on this device (iOS < 26, AI-ineligible hardware, or
    /// Apple Intelligence disabled in Settings) — caller should fall back
    /// to BYOK or show the setup chooser.
    @discardableResult
    static func installFoundationModelsBackend() -> Bool {
        guard hasFoundationModels else { return false }
        let svc = LocalAIService.shared
        if svc.activeBackendType == .remote {
            svc.clearRemoteBackend()
        }
        svc.useFoundationModelsBackend()
        return true
    }

    /// Flip the preferred backend and install it. Used by the in-chat
    /// cpu/cloud toggle. No-op when the requested backend isn't actually
    /// available (the toggle would never have been visible in that case).
    @discardableResult
    static func toggle(to backend: AIBackendType) async -> Bool {
        Preferences.preferredAIBackend = backend
        return await applyPreferredBackend()
    }
}
