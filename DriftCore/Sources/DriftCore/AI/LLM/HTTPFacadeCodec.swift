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

    /// Encodes a `URLRequest` into the primitives `HttpFacade.kt#post` expects
    /// to cross the Skip reflection bridge (String/Int64 only).
    public static func encodeRequest(_ request: URLRequest) -> (url: String, headersJson: String, bodyBase64: String, timeoutMillis: Int64) {
        let url = request.url?.absoluteString ?? ""
        let headers = request.allHTTPHeaderFields ?? [:]
        let headersJson = (try? JSONSerialization.data(withJSONObject: headers))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let bodyBase64 = (request.httpBody ?? Data()).base64EncodedString()
        // RemoteLLMBackend sets request.timeoutInterval = effectiveTimeout, so
        // the app's per-call deadline rides along as OkHttp's callTimeout.
        let timeoutMillis = Int64(max(1, request.timeoutInterval) * 1000)
        return (url, headersJson, bodyBase64, timeoutMillis)
    }

    /// Decodes `HttpFacade.kt#post`'s `{"status":Int,"bodyBase64":String}`
    /// reply. `status < 0` means the Kotlin side caught an exception (timeout,
    /// unreachable host, …) — mapped to `.timedOut` so `RemoteLLMBackend`'s
    /// existing transient-error handling applies unchanged.
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
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw DecodeError.malformed
        }
        return (body, response)
    }
}
