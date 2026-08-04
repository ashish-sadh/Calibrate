import Foundation
import SkipFuse
import DriftCore

/// OkHttp-backed HTTPDataSession — the Android half of the
/// `DriftPlatform.httpSession` seam, and since #1194 the transport for ALL of
/// DriftCore's networking (Coach/vision, Supabase sharing + auth, online food
/// lookup, Coach web tools), not just RemoteLLMBackend (#1136).
/// swift-corelibs-foundation's URLSession.data(for:) parks non-cancellably on
/// Skip (its completion handler never fires), so every one of those hung
/// forever — sharing since it shipped, silently, because no Android device
/// could ever complete the anonymous sign-up. `HttpFacade.kt`'s blocking
/// OkHttp `execute()` is bounded by `callTimeout`, so the continuation
/// dispatching it always resumes.
public final class AndroidHTTPSession: HTTPDataSession, @unchecked Sendable {
    public init() {}

    private static let facadeClass = "drift.android.HttpFacade"

    private static func onFacadeQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Blocking OkHttp execute() stays off-Main (no ANR). But unlike
                // Apple's runtime, Skip does NOT re-hop the awaiting @MainActor
                // chain back to Main when a continuation resumes from a foreign
                // thread — it continues on whatever thread called resume(). That
                // stranded the entire cloud reply pipeline off-Main (#1180), so
                // resume from a MainActor task instead.
                do {
                    let value = try work()
                    Task { @MainActor in continuation.resume(returning: value) }
                } catch {
                    nonisolated(unsafe) let err = error
                    Task { @MainActor in continuation.resume(throwing: err) }
                }
            }
        }
    }

    // The JNI bridge exists only in the Android compile; Skip's Darwin
    // bridging pass compiles this same file for iphonesimulator, so the
    // facade touchpoint lives behind one #if with an inert Darwin stub.
    // The reflective bridge has no compile-time name check — the Kotlin
    // signature and this call site must always move in the same commit, or
    // every call silently returns {"status":-1} at runtime.
    #if os(Android)
    private static func facadeRequest(_ url: String, _ method: String, _ headersJson: String, _ bodyBase64: String, _ timeoutMillis: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).request(url, method, headersJson, bodyBase64, timeoutMillis) as String? ?? "{\"status\":-1}"
    }
    #else
    private static func facadeRequest(_ url: String, _ method: String, _ headersJson: String, _ bodyBase64: String, _ timeoutMillis: Int64) throws -> String {
        "{\"status\":-1}"
    }
    #endif

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let encoded = HTTPFacadeCodec.encodeRequest(request)
        let raw = try await Self.onFacadeQueue {
            try Self.facadeRequest(encoded.url, encoded.method, encoded.headersJson, encoded.bodyBase64, encoded.timeoutMillis)
        }
        let decoded = try HTTPFacadeCodec.decodeResponse(raw, url: request.url ?? URL(string: "https://invalid")!)
        // Every cloud bug this seam has produced (#1133, #1136, #1177) was
        // invisible from Swift: the reply arrives as a plain 200 and the damage
        // only surfaces as an empty parse three layers up. A reply that is
        // implausibly small for its status is the tell. Method, sizes and
        // status ONLY — request bodies carry the API key and response bodies
        // carry the user's meal, and neither belongs in logcat.
        logger.info("AndroidHTTPSession: \(encoded.method) \(encoded.bodyBase64.count)B(b64) → HTTP \((decoded.1 as? HTTPURLResponse)?.statusCode ?? -1), \(decoded.0.count)B")
        return decoded
    }
}
