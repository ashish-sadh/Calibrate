// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  ARCHIVED — NOT COMPILED.                                                  ║
// ║  This folder (Drift/Archive) is excluded from the Drift target in          ║
// ║  project.yml (sources excludes: ["Archive"]). Preserved for reference;     ║
// ║  do not delete.                                                            ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// Legacy "bring your own key" (BYOK) chat backend path. Drift Coach now runs on
// a Nebius team key from AppConfig (see AIBackendCoordinator.installCoachBackend),
// so the chat no longer reuses the Photo Log Keychain entry. This code is kept
// because the BYOK plumbing took real effort and may return as a user-facing
// option later. Photo Log still uses BYOK via its OWN path (PhotoLogTool +
// CloudVisionKey) — that is untouched and lives in the compiled target.
//
// To restore: move this file out of Archive/, re-point
// AIBackendCoordinator.applyPreferredBackend()'s `.remote` case back to
// installRemoteBackend(), and restore `remoteProvider(for:)` + the
// CloudVisionKey-backed `hasRemoteKey` check.

#if false

import Foundation
import DriftCore

extension AIBackendCoordinator {

    /// Whether a remote BYOK key is configured for the current photo-log
    /// provider. Metadata-only Keychain query — no biometric prompt.
    static var hasRemoteKey: Bool {
        CloudVisionKey.has(provider: Preferences.photoLogProvider)
    }

    /// Translate the photo-log `CloudVisionProvider` to the chat-side
    /// `RemoteLLMBackend.Provider`. The two enums share rawValues so the
    /// mapping is direct, but going through this helper keeps the iOS
    /// app's Keychain enum decoupled from DriftCore's HTTP provider type.
    static func remoteProvider(for cloud: CloudVisionProvider) -> RemoteLLMBackend.Provider {
        switch cloud {
        case .anthropic: return .anthropic
        case .openai:    return .openai
        case .gemini:    return .gemini
        }
    }

    /// Install the remote BYOK backend using the photo-log provider+model.
    /// Reuses the same Keychain entry the user already configured for Photo
    /// Log — no separate setup step. Returns false when no key is stored
    /// (user hit the toggle without setting up a provider first).
    @discardableResult
    static func installRemoteBackend() async -> Bool {
        guard hasRemoteKey else { return false }
        let cloud = Preferences.photoLogProvider
        do {
            guard let key = try await CloudVisionKey.get(for: cloud) else { return false }
            let model = Preferences.photoLogModel(for: cloud)
            LocalAIService.shared.useRemoteBackend(
                provider: remoteProvider(for: cloud),
                modelID: model,
                apiKey: key
            )
            return true
        } catch {
            Log.app.error("AIBackendCoordinator: failed to load key for \(cloud.rawValue): \(error)")
            return false
        }
    }
}

#endif
