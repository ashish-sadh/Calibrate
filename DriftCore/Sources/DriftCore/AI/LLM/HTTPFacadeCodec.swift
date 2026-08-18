import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Pure marshalling for the Android HTTP facade seam (#1136). Kept here (not
/// in the Android adapter) so the error-prone request/response marshalling is
/// Tier-0 tested; the Skip adapter (`AndroidHTTPSession`) becomes a trivial
/// shell that just calls through to the Kotlin `HttpFacade`.
public enum HTTPFacadeCodec {
    public enum DecodeError: Error, Equatable {
        case malformed
    }

    /// Encodes a `URLRequest` into the primitives `HttpFacade.kt#request`
    /// expects to cross the Skip reflection bridge (String/Int64 only).
    public static func encodeRequest(_ request: URLRequest) -> (url: String, method: String, headersJson: String, bodyBase64: String, timeoutMillis: Int64) {
        let url = request.url?.absoluteString ?? ""
        // Dropping the method sent every GET/PATCH/DELETE out as a POST (#1194)
        // — invisible on the LLM path, which is POST-only, but it silently
        // corrupts PostgREST reads and writes. `URLRequest` leaves this nil for
        // a plain read, which is exactly Foundation's own GET default.
        let method = (request.httpMethod ?? "GET").uppercased()
        let headers = request.allHTTPHeaderFields ?? [:]
        let headersJson = (try? JSONSerialization.data(withJSONObject: headers))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let bodyBase64 = (request.httpBody ?? Data()).base64EncodedString()
        // RemoteLLMBackend sets request.timeoutInterval = effectiveTimeout, so
        // the app's per-call deadline rides along as OkHttp's callTimeout.
        let timeoutMillis = Int64(max(1, request.timeoutInterval) * 1000)
        return (url, method, headersJson, bodyBase64, timeoutMillis)
    }

    /// Which endpoint a log line is about, with nothing identifying in it.
    /// Sizes-only logging is what made #1251 cost a JWT replay to diagnose —
    /// nine reads in one Friends-hub load all logged as `GET → 200, 2B`, and
    /// which TABLE each one hit was the whole question. Endpoint plus the first
    /// query KEY (`profiles?id`, `friendships?status`) answers it and still
    /// carries no user IDs, no handles and no tokens.
    public static func endpointSignature(_ url: String) -> String {
        let tail = url.components(separatedBy: "/v1/").last ?? url
        guard let q = tail.firstIndex(of: "?") else { return tail }
        let table = String(tail[..<q])
        let firstKey = tail[tail.index(after: q)...]
            .components(separatedBy: "&").first?
            .components(separatedBy: "=").first ?? ""
        return firstKey.isEmpty ? table : "\(table)?\(firstKey)"
    }

    /// Decodes `HttpFacade.kt#request`'s
    /// `{"status":Int,"bodyBase64":String,"headersJson":String}` reply.
    /// `status < 0` means the Kotlin side caught an exception (timeout,
    /// unreachable host, …) — mapped to `.timedOut` so `RemoteLLMBackend`'s
    /// existing transient-error handling applies unchanged. `headersJson` is
    /// optional: the `status:-1` error object carries none, and neither did
    /// older facade builds.
    public static func decodeResponse(_ raw: String, url: URL) throws -> (Data, URLResponse) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? Int
        else {
            throw DecodeError.malformed
        }
        if status < 0 {
            throw URLError(.timedOut)
        }
        let bodyBase64 = obj["bodyBase64"] as? String ?? ""
        let body = Data(base64Encoded: bodyBase64) ?? Data()
        let headerFields = (obj["headersJson"] as? String)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headerFields) else {
            throw DecodeError.malformed
        }
        return (body, response)
    }
}
