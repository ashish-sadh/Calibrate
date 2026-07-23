import Foundation

/// Shared request policy for STRUCTURED-EXTRACTION cloud turns — the calls that
/// transcribe user input into JSON (meal text, exercise text, workout photo
/// scans) as opposed to conversational chat. Exists because the workout-scan
/// field debugging (2026-07-22, builds 358-360) exposed that every extraction
/// path had silently inherited chat-turn economics, and each inherited defect
/// was a real user-facing failure:
///
/// - chat's 512-token ceiling truncated big extractions mid-JSON (a full
///   notebook page; equally a 12-item thali) → bogus "couldn't reach the cloud"
/// - provider-default sampling temperature made the SAME input parse into
///   DIFFERENT numbers run-to-run — transcription must be greedy
/// - a transient network blip cost the user the whole wait with no second try
///
/// One policy, referenced by every extraction call site, so the next
/// extraction feature can't re-inherit chat defaults by accident.
public enum CloudExtractionPolicy {

    /// Extraction is transcription, not conversation — pin greedy decoding.
    /// (Provider serving is still not bit-deterministic across requests, but
    /// temp 0 removed the run-to-run weight confabulation observed live.)
    public static let temperature: Double = 0

    /// Text extractions (meal / exercise JSON). Chat uses 512; a many-item
    /// meal or long workout needs headroom, and unused budget costs nothing.
    public static let textMaxTokens = 1024

    /// One automatic retry, TRANSIENT faults only. A dropped connection or
    /// provider 5xx can succeed a second later; auth/rate/quota fail
    /// identically twice (they need the user), and an undecodable reply is
    /// deterministic at temp 0 — retrying only doubles the wait.
    public static func isRetryable(_ err: RemoteBackendError?) -> Bool {
        if case .transient = err { return true }
        return false
    }

    /// Run `attempt` up to twice, retrying once when the first miss is
    /// transient per `isRetryable`. `nil` from `attempt` means failure;
    /// `onRetry` lets the UI surface the second try.
    @MainActor
    public static func withRetry<T: Sendable>(
        onRetry: (() -> Void)? = nil,
        _ attempt: () async -> T?
    ) async -> T? {
        if let first = await attempt() { return first }
        guard isRetryable(LocalAIService.shared.lastRemoteError) else { return nil }
        onRetry?()
        return await attempt()
    }
}
