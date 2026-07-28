import Foundation
import SkipFuse
import DriftCore

/// OkHttp-backed HTTPDataSession for RemoteLLMBackend (#1136) — the Android
/// half of the `DriftPlatform.httpSession` seam. swift-corelibs-foundation's
/// URLSession.data(for:) parks non-cancellably on Skip (its completion
/// handler never fires), so Coach chat, meal/photo parsing, and workout scan
/// all hung forever. `HttpFacade.kt`'s blocking OkHttp `execute()` is bounded
/// by `callTimeout`, so the continuation dispatching it always resumes.
public final class AndroidHTTPSession: HTTPDataSession, @unchecked Sendable {
    public init() {}

    private static let facadeClass = "drift.android.HttpFacade"

    private static func onFacadeQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // The JNI bridge exists only in the Android compile; Skip's Darwin
    // bridging pass compiles this same file for iphonesimulator, so the
    // facade touchpoint lives behind one #if with an inert Darwin stub.
    #if os(Android)
    private static func facadePost(_ url: String, _ headersJson: String, _ bodyBase64: String, _ timeoutMillis: Int64) throws -> String {
        try AnyDynamicObject(className: facadeClass, arguments: []).post(url, headersJson, bodyBase64, timeoutMillis) as String? ?? "{\"status\":-1}"
    }
    #else
    private static func facadePost(_ url: String, _ headersJson: String, _ bodyBase64: String, _ timeoutMillis: Int64) throws -> String {
        "{\"status\":-1}"
    }
    #endif

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let encoded = HTTPFacadeCodec.encodeRequest(request)
        let raw = try await Self.onFacadeQueue {
            try Self.facadePost(encoded.url, encoded.headersJson, encoded.bodyBase64, encoded.timeoutMillis)
        }
        return try HTTPFacadeCodec.decodeResponse(raw, url: request.url ?? URL(string: "https://invalid")!)
    }
}
