import Foundation
import Testing
@testable import Drift

// MARK: - URLProtocol stub

/// Intercepts every request made by an `ephemeral` URLSession configured
/// with this class. Lets us assert on the outgoing request and control the
/// response without hitting the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, Data))? = nil
    nonisolated(unsafe) static var error: URLError? = nil
    nonisolated(unsafe) static var lastRequest: URLRequest? = nil

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        if let err = StubURLProtocol.error {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let (status, body) = StubURLProtocol.responder?(request) ?? (200, Data())
        let http = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* no-op */ }

    static func reset() {
        responder = nil
        error = nil
        lastRequest = nil
    }
}

private func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Happy path

@Test func anthropicSuccessParsesToolUseInput() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = """
        {
          "id": "msg_123",
          "type": "message",
          "role": "assistant",
          "content": [
            {
              "type": "tool_use",
              "id": "toolu_1",
              "name": "food_log",
              "input": {
                "items": [
                  {
                    "name": "grilled salmon",
                    "grams": 180,
                    "calories": 320,
                    "protein_g": 34,
                    "carbs_g": 0,
                    "fat_g": 18,
                    "confidence": "high"
                  }
                ],
                "overall_confidence": "medium",
                "notes": "Dinner plate assumption."
              }
            }
          ]
        }
        """
        return (200, Data(body.utf8))
    }
    let client = AnthropicVisionClient(apiKey: "sk-fake", session: stubbedSession())
    let resp = try await client.analyze(image: Data([0xff, 0xd8]), prompt: "what is this?")
    #expect(resp.items.count == 1)
    #expect(resp.items[0].name == "grilled salmon")
    #expect(resp.items[0].calories == 320)
    #expect(resp.overallConfidence == .medium)
    #expect(resp.notes == "Dinner plate assumption.")
}

@Test func anthropicRequestIncludesApiKeyAndVersionHeaders() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = #"{"content":[{"type":"tool_use","input":{"items":[],"overall_confidence":"low"}}]}"#
        return (200, Data(body.utf8))
    }
    let client = AnthropicVisionClient(apiKey: "sk-hidden", session: stubbedSession())
    _ = try? await client.analyze(image: Data([0xff]), prompt: "hi")
    let req = StubURLProtocol.lastRequest
    #expect(req?.value(forHTTPHeaderField: "x-api-key") == "sk-hidden")
    #expect(req?.value(forHTTPHeaderField: "anthropic-version") == AnthropicVisionClient.apiVersion)
    #expect(req?.value(forHTTPHeaderField: "content-type") == "application/json")
    #expect(req?.httpMethod == "POST")
}

// MARK: - Errors

@Test func anthropic401MapsToUnauthorized() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (401, Data(#"{"error":"invalid api key"}"#.utf8)) }
    let client = AnthropicVisionClient(apiKey: "bad", session: stubbedSession())
    await #expect(throws: CloudVisionError.unauthorized) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func anthropic429MapsToRateLimited() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (429, Data(#"{"error":"rate limit"}"#.utf8)) }
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.rateLimited) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func anthropic500MapsToBadResponse() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (500, Data()) }
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.badResponse(500)) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func anthropicMalformedBodyMapsToMalformedPayload() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data("not json at all".utf8)) }
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.malformedPayload) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func anthropicMissingToolUseMapsToMalformedPayload() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        // Valid Messages payload with no tool_use block
        let body = #"{"content":[{"type":"text","text":"hello"}]}"#
        return (200, Data(body.utf8))
    }
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.malformedPayload) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func anthropicOfflineMapsToOffline() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.error = URLError(.notConnectedToInternet)
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.offline) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
    StubURLProtocol.reset()
}

@Test func anthropicTimeoutMapsToTimeout() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.error = URLError(.timedOut)
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.timeout) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
    StubURLProtocol.reset()
}

// MARK: - Body construction

@Test func bodyContainsModelAndImageAndToolChoice() throws {
    let data = try AnthropicVisionClient.body(
        model: "claude-sonnet-4-6",
        image: Data([0x01, 0x02, 0x03]),
        prompt: "log this"
    )
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["model"] as? String == "claude-sonnet-4-6")
    #expect((json?["tool_choice"] as? [String: Any])?["name"] as? String == "food_log")
    let tools = json?["tools"] as? [[String: Any]]
    #expect(tools?.first?["name"] as? String == "food_log")
    // Verify image block is present and base64-encoded
    let messages = json?["messages"] as? [[String: Any]]
    let content = messages?.first?["content"] as? [[String: Any]]
    let imageBlock = content?.first { ($0["type"] as? String) == "image" }
    let source = imageBlock?["source"] as? [String: Any]
    #expect(source?["type"] as? String == "base64")
    #expect(source?["media_type"] as? String == "image/jpeg")
    #expect(source?["data"] as? String == Data([0x01, 0x02, 0x03]).base64EncodedString())
}

// MARK: - Response schema lenience

@Test func responseDefaultsMissingMacrosToZero() throws {
    let body = """
    {
      "content": [
        {
          "type": "tool_use",
          "input": {
            "items": [{"name": "apple", "confidence": "low"}],
            "overall_confidence": "low"
          }
        }
      ]
    }
    """
    let parsed = try AnthropicVisionClient.parseResponse(Data(body.utf8))
    #expect(parsed.items.count == 1)
    #expect(parsed.items[0].grams == 0)
    #expect(parsed.items[0].calories == 0)
    #expect(parsed.items[0].proteinG == 0)
    #expect(parsed.items[0].carbsG == 0)
    #expect(parsed.items[0].fatG == 0)
    #expect(parsed.items[0].confidence == .low)
}

@Test func responseAcceptsMixedCaseConfidence() throws {
    let body = """
    {
      "content": [
        {
          "type": "tool_use",
          "input": {
            "items": [{"name": "rice", "grams": 150, "calories": 200, "protein_g": 4, "carbs_g": 44, "fat_g": 0, "confidence": "Medium"}],
            "overall_confidence": "HIGH"
          }
        }
      ]
    }
    """
    let parsed = try AnthropicVisionClient.parseResponse(Data(body.utf8))
    #expect(parsed.items[0].confidence == .medium)
    #expect(parsed.overallConfidence == .high)
}

@Test func responseUnknownConfidenceFallsBackToLow() throws {
    let body = """
    {
      "content": [
        {
          "type": "tool_use",
          "input": {
            "items": [{"name": "rice", "confidence": "very_sure"}],
            "overall_confidence": "pretty_sure"
          }
        }
      ]
    }
    """
    let parsed = try AnthropicVisionClient.parseResponse(Data(body.utf8))
    #expect(parsed.items[0].confidence == .low)
    #expect(parsed.overallConfidence == .low)
}
