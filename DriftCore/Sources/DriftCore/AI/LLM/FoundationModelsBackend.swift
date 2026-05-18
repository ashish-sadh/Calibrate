import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Foundation Models backend

/// `AIBackend` over Apple's `FoundationModels` framework (iOS 26+, macOS 26+).
/// On-device, system-managed weights, zero per-call cost. No model files
/// shipped, no download flow.
///
/// Three design decisions are load-bearing (see Docs/designs/662-foundation-models.md):
///
/// 1. **Per-call session lifecycle.** A single `LanguageModelSession` reused
///    across calls accumulates a hidden transcript and throws
///    `exceededContextWindowSize` after ~20–30 sequential prompts. Every
///    `respond` / `respondStreaming` creates a fresh session.
/// 2. **Permissive guardrails.** Drift's surface is data extraction
///    ("delete the eggs I just logged"), not advice generation. The
///    `.default` preset refuses harmless data-mutation phrasing because the
///    model interprets *delete*/*remove* as harm signals in some contexts.
///    `.permissiveContentTransformations` matches the extraction use case.
/// 3. **`isLoaded` reflects `SystemLanguageModel.default.isAvailable`.** The
///    framework owns weight resolution + download; we have no separate
///    load step. `load()` is a no-op so the chat layer's state machine
///    treats "FM available on this device" the same as "model file is on
///    disk" for the local case.
///
/// **Vision is unsupported.** FM is text-only on iOS 26.x; `supportsVision`
/// returns false. Photo-log routes through the existing BYOK + cloud vision
/// surfaces (`CloudVisionClient`), unchanged.
public final class FoundationModelsBackend: AIBackend, @unchecked Sendable {

    public init() {}

    /// True when the OS reports `SystemLanguageModel.default.isAvailable` —
    /// i.e. iOS 26+ on Apple-Intelligence-eligible hardware (A17 Pro /
    /// M-series / A19 Pro) with Apple Intelligence turned on. Computed
    /// per-call so a mid-session change (user toggles AI off in Settings)
    /// is reflected without a process restart.
    public var isLoaded: Bool {
        Self.isAvailableNow
    }

    /// FM is text-only on iOS 26.x — no image input parameter on the
    /// generation APIs. Photo-log keeps using the cloud-vision path.
    public var supportsVision: Bool { false }

    /// FM is system-managed — there is no app-side download or memory
    /// load step. We treat availability as the only "loaded" signal.
    public func load() async throws { /* no-op */ }

    /// One-shot non-streaming response. Creates a fresh session.
    /// Public so the Tier-3 parity gate in `DriftLLMEvalMacOS` can drive it
    /// directly with the same `(prompt, systemPrompt)` signature it uses for
    /// `LlamaCppBackend.respond` — see `FoundationModelsChatParityTests` (#791).
    public func respond(to prompt: String, systemPrompt: String) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard Self.isAvailableNow else { return "" }
            do {
                let session = Self.makeSession(systemPrompt: systemPrompt)
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                // Don't surface FM-internal error text to the chat layer;
                // empty-string keeps the contract aligned with the existing
                // `AIBackend.respond` shape (which doesn't throw).
                return ""
            }
        }
        return ""
#else
        return ""
#endif
    }

    /// Streaming response. Emits incremental token chunks via `onToken`.
    /// Returns the full accumulated string at the end.
    ///
    /// FM's `streamResponse(to:)` returns an `AsyncSequence` of partial
    /// strings where each emission contains the *cumulative* response so
    /// far. We diff-emit so `onToken` callers see the new fragment, not
    /// the full prefix every time (matches `LlamaCppBackend`'s contract).
    func respondStreaming(
        to prompt: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard Self.isAvailableNow else { return "" }
            let session = Self.makeSession(systemPrompt: systemPrompt)
            var accumulated = ""
            do {
                for try await partial in session.streamResponse(to: prompt) {
                    let next = partial.content
                    if next.count > accumulated.count {
                        let newFragment = String(next.dropFirst(accumulated.count))
                        accumulated = next
                        onToken(newFragment)
                    }
                }
                return accumulated
            } catch {
                return accumulated
            }
        }
        return ""
#else
        return ""
#endif
    }

    /// No memory to free — FM weights live in the system, not the process.
    func unload() { /* no-op */ }

    // MARK: - Private

    /// Centralised availability check so the `#available` gating + the
    /// Apple-Intelligence runtime flag aren't sprinkled across each entry
    /// point. Public so the iOS coordinator can decide whether the
    /// `.foundationModels` backend is a reachable preference.
    public static var isAvailableNow: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
#else
        return false
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func makeSession(systemPrompt: String) -> LanguageModelSession {
        // Permissive preset per #662 lesson: default preset refuses harmless
        // data-mutation phrasing in Drift's extraction surface.
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        if systemPrompt.isEmpty {
            return LanguageModelSession(model: model)
        }
        return LanguageModelSession(model: model, instructions: systemPrompt)
    }
#endif
}
