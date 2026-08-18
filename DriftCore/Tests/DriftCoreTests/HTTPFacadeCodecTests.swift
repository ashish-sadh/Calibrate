import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DriftCore
import Testing

/// Tier-0 coverage for the Android HTTP facade marshalling (#1136). This is
/// the pure-Swift half of the OkHttp facade seam — the Kotlin side
/// (`HttpFacade.kt`) and the `AnyDynamicObject` bridge (`AndroidHTTPSession`)
/// aren't reachable from a macOS/Linux test host, so everything error-prone
/// (header/body marshalling, status→error mapping) lives here instead.
struct HTTPFacadeCodecTests {

    // MARK: - encodeRequest

    @Test func encodeRequestRoundTripsHeadersBodyAndTimeout() {
        var request = URLRequest(url: URL(string: "https://api.studio.nebius.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer k", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"model":"m"}"#.utf8)
        request.timeoutInterval = 60

        let encoded = HTTPFacadeCodec.encodeRequest(request)

        #expect(encoded.url == "https://api.studio.nebius.ai/v1/chat/completions")
        #expect(encoded.timeoutMillis == 60_000)
        #expect(Data(base64Encoded: encoded.bodyBase64) == request.httpBody)

        let headers = try! JSONSerialization.jsonObject(with: Data(encoded.headersJson.utf8)) as! [String: String]
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["Authorization"] == "Bearer k")
    }

    @Test func encodeRequestFloorsTimeoutAtOneSecond() {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.timeoutInterval = 0
        let encoded = HTTPFacadeCodec.encodeRequest(request)
        #expect(encoded.timeoutMillis == 1000)
    }

    @Test func encodeRequestWithNoBodyEncodesEmptyString() {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let encoded = HTTPFacadeCodec.encodeRequest(request)
        #expect(Data(base64Encoded: encoded.bodyBase64) == Data())
    }

    /// #1194: the codec used to drop `httpMethod`, so every PostgREST GET/
    /// PATCH/DELETE went out as a POST once sharing moved onto this seam.
    @Test(arguments: ["GET", "POST", "PATCH", "DELETE", "HEAD"])
    func encodeRequestForwardsExplicitMethod(method: String) {
        var request = URLRequest(url: URL(string: "https://project.supabase.co/rest/v1/profiles")!)
        request.httpMethod = method
        #expect(HTTPFacadeCodec.encodeRequest(request).method == method)
    }

    @Test func encodeRequestDefaultsToGETWhenMethodUnset() {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.httpMethod = nil
        #expect(HTTPFacadeCodec.encodeRequest(request).method == "GET")
    }

    @Test func encodeRequestUppercasesMethodForOkHttpBodyRule() {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.httpMethod = "patch"
        #expect(HTTPFacadeCodec.encodeRequest(request).method == "PATCH")
    }

    // MARK: - decodeResponse

    @Test func decodeResponseWithStatus200ReturnsData() throws {
        let payload = Data(#"{"reply":"hi"}"#.utf8)
        let raw = #"{"status":200,"bodyBase64":"\#(payload.base64EncodedString())"}"#
        let (data, response) = try HTTPFacadeCodec.decodeResponse(raw, url: URL(string: "https://example.com")!)
        #expect(data == payload)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func decodeResponsePreservesNon200StatusForCategorization() throws {
        let raw = #"{"status":429,"bodyBase64":""}"#
        let (_, response) = try HTTPFacadeCodec.decodeResponse(raw, url: URL(string: "https://example.com")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 429)
    }

    @Test func decodeResponseWithNegativeStatusThrowsTimedOut() {
        let raw = #"{"status":-1,"error":"unreachable"}"#
        #expect(throws: URLError.self) {
            _ = try HTTPFacadeCodec.decodeResponse(raw, url: URL(string: "https://example.com")!)
        }
    }

    @Test func decodeResponseWithMalformedJSONThrows() {
        #expect(throws: HTTPFacadeCodec.DecodeError.self) {
            _ = try HTTPFacadeCodec.decodeResponse("not json", url: URL(string: "https://example.com")!)
        }
    }

    /// #1194: `headerFields: nil` was harmless while RemoteLLMBackend was the
    /// only consumer, but PostgREST returns the row count in `Content-Range`.
    @Test func decodeResponseRoundTripsResponseHeaders() throws {
        // `headersJson` nests as a *string* field, exactly as HttpFacade.kt
        // emits it — build the reply through JSONSerialization so the escaping
        // is the real thing rather than a hand-written approximation.
        let reply = try JSONSerialization.data(withJSONObject: [
            "status": 200,
            "bodyBase64": "",
            "headersJson": #"{"Content-Range":"0-4/42","Content-Type":"application/json"}"#,
        ])
        let raw = try #require(String(data: reply, encoding: .utf8))

        let (_, response) = try HTTPFacadeCodec.decodeResponse(raw, url: URL(string: "https://example.com")!)

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.value(forHTTPHeaderField: "Content-Range") == "0-4/42")
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    /// A reply from an older facade build (or the `status:-1` error object,
    /// which carries no headers at all) must still decode.
    @Test func decodeResponseWithoutHeadersJSONStillDecodes() throws {
        let payload = Data(#"[{"id":1}]"#.utf8)
        let raw = #"{"status":200,"bodyBase64":"\#(payload.base64EncodedString())"}"#
        let (data, response) = try HTTPFacadeCodec.decodeResponse(raw, url: URL(string: "https://example.com")!)
        #expect(data == payload)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    // MARK: Endpoint signature (#1251)

    /// The whole point is that a log line says WHICH table without saying WHO.
    @Test func endpointSignatureNamesTheTableAndFirstKeyOnly() {
        #expect(HTTPFacadeCodec.endpointSignature(
            "https://x.supabase.co/rest/v1/profiles?id=in.(abc-123,def-456)&select=id,username")
            == "profiles?id")
        #expect(HTTPFacadeCodec.endpointSignature(
            "https://x.supabase.co/rest/v1/friendships?status=eq.accepted&or=(requester_id.eq.abc)")
            == "friendships?status")
        #expect(HTTPFacadeCodec.endpointSignature(
            "https://x.supabase.co/auth/v1/token?grant_type=refresh_token")
            == "token?grant_type")
        #expect(HTTPFacadeCodec.endpointSignature("https://x.supabase.co/rest/v1/messages")
            == "messages")
    }

    /// No UUID, handle, token or column VALUE may survive into the signature —
    /// this is a logcat line on a user's phone.
    @Test func endpointSignatureLeaksNoValues() {
        let uid = "cf600644-ceb9-4185-8308-f9d03689f159"
        let sig = HTTPFacadeCodec.endpointSignature(
            "https://x.supabase.co/rest/v1/profiles?id=eq.\(uid)&select=discoverable&limit=1")
        #expect(sig == "profiles?id")
        #expect(!sig.contains(uid))
        #expect(!sig.contains("discoverable"))
    }

    /// A URL the codec can't parse degrades to the raw string rather than
    /// crashing or logging nothing at all.
    @Test func endpointSignatureFallsBackToTheWholeString() {
        #expect(HTTPFacadeCodec.endpointSignature("not-a-url") == "not-a-url")
    }
}
