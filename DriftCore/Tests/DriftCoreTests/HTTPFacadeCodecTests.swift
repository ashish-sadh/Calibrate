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
}
