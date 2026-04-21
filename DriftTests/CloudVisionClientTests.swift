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

// MARK: - providerError surfacing

@Test func anthropic400WithErrorMessageMapsToProviderError() async throws {
    // Replicates the 2026-04-21 "credit balance too low" response that was
    // previously being hidden behind a generic .badResponse(400).
    StubURLProtocol.reset()
    let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#
    StubURLProtocol.responder = { _ in (400, Data(body.utf8)) }
    let client = AnthropicVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.providerError(status: 400, message: "Your credit balance is too low to access the Anthropic API.")) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func errorMessageExtractorReturnsNilOnNonStandardShape() {
    // Falls back to .badResponse(code) when the body isn't the expected
    // {error:{message}} shape.
    #expect(AnthropicVisionClient.extractErrorMessage(Data("not json".utf8)) == nil)
    #expect(AnthropicVisionClient.extractErrorMessage(Data(#"{"foo":"bar"}"#.utf8)) == nil)
    #expect(AnthropicVisionClient.extractErrorMessage(Data(#"{"error":"just a string"}"#.utf8)) == nil)
    #expect(AnthropicVisionClient.extractErrorMessage(Data(#"{"error":{"type":"x"}}"#.utf8)) == nil)
    #expect(AnthropicVisionClient.extractErrorMessage(Data(#"{"error":{"message":""}}"#.utf8)) == nil)
    #expect(AnthropicVisionClient.extractErrorMessage(Data(#"{"error":{"message":"real"}}"#.utf8)) == "real")
}

// MARK: - OpenAI

@Test func openaiSuccessParsesToolCallArguments() async throws {
    // OpenAI returns arguments as a JSON *string* under
    // choices[0].message.tool_calls[0].function.arguments.
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let argumentsJSON = #"{\"items\":[{\"name\":\"caesar salad\",\"grams\":210,\"calories\":350,\"protein_g\":12,\"carbs_g\":20,\"fat_g\":25,\"confidence\":\"medium\"}],\"overall_confidence\":\"medium\",\"notes\":\"Assumed dressing included.\"}"#
        let body = """
        {
          "id": "chatcmpl-fake",
          "choices": [{
            "index": 0,
            "message": {
              "role": "assistant",
              "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": {
                  "name": "food_log",
                  "arguments": "\(argumentsJSON)"
                }
              }]
            },
            "finish_reason": "tool_calls"
          }]
        }
        """
        return (200, Data(body.utf8))
    }
    let client = OpenAIVisionClient(apiKey: "sk-fake", session: stubbedSession())
    let resp = try await client.analyze(image: Data([0xff, 0xd8]), prompt: "what is this?")
    #expect(resp.items.count == 1)
    #expect(resp.items[0].name == "caesar salad")
    #expect(resp.items[0].calories == 350)
    #expect(resp.overallConfidence == .medium)
    #expect(resp.notes == "Assumed dressing included.")
}

@Test func openaiRequestHasBearerAuthAndForcedFunctionCall() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = #"{"choices":[{"message":{"tool_calls":[{"function":{"name":"food_log","arguments":"{\"items\":[],\"overall_confidence\":\"low\"}"}}]}}]}"#
        return (200, Data(body.utf8))
    }
    let client = OpenAIVisionClient(apiKey: "sk-secret", session: stubbedSession())
    _ = try? await client.analyze(image: Data([0xff]), prompt: "hi")
    let req = StubURLProtocol.lastRequest
    #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
    #expect(req?.value(forHTTPHeaderField: "content-type") == "application/json")
    #expect(req?.httpMethod == "POST")
}

@Test func openai401MapsToUnauthorized() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (401, Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8)) }
    let client = OpenAIVisionClient(apiKey: "bad", session: stubbedSession())
    await #expect(throws: CloudVisionError.unauthorized) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func openai400WithUnsupportedImageMapsToProviderError() async throws {
    StubURLProtocol.reset()
    let body = #"{"error":{"type":"invalid_request_error","code":"invalid_image","message":"You uploaded an unsupported image."}}"#
    StubURLProtocol.responder = { _ in (400, Data(body.utf8)) }
    let client = OpenAIVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.providerError(status: 400, message: "You uploaded an unsupported image.")) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func openaiMissingToolCallsMapsToMalformedPayload() async throws {
    StubURLProtocol.reset()
    // Plain-text response (no tool_calls) — model declined to call the
    // function despite tool_choice. Surface as malformed so the user sees a
    // clear error instead of a silent empty result.
    StubURLProtocol.responder = { _ in
        let body = #"{"choices":[{"message":{"role":"assistant","content":"I can't identify that image."}}]}"#
        return (200, Data(body.utf8))
    }
    let client = OpenAIVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.malformedPayload) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func openaiBodyShapesImageAsDataURL() throws {
    let data = try OpenAIVisionClient.body(
        model: "gpt-4o-mini",
        image: Data([0x01, 0x02, 0x03]),
        prompt: "log this"
    )
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["model"] as? String == "gpt-4o-mini")
    // tool_choice shape
    let toolChoice = json?["tool_choice"] as? [String: Any]
    #expect(toolChoice?["type"] as? String == "function")
    #expect((toolChoice?["function"] as? [String: Any])?["name"] as? String == "food_log")
    // Image sent as data: URL
    let messages = json?["messages"] as? [[String: Any]]
    let content = messages?.first?["content"] as? [[String: Any]]
    let imageBlock = content?.first { ($0["type"] as? String) == "image_url" }
    let url = (imageBlock?["image_url"] as? [String: Any])?["url"] as? String
    #expect(url?.hasPrefix("data:image/jpeg;base64,") == true)
    #expect(url?.contains(Data([0x01, 0x02, 0x03]).base64EncodedString()) == true)
}

// MARK: - Gemini

@Test func geminiSuccessParsesFunctionCallArgs() async throws {
    // Gemini returns args as an already-parsed JSON object under
    // candidates[0].content.parts[].functionCall.args.
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = """
        {
          "candidates": [{
            "content": {
              "parts": [{
                "functionCall": {
                  "name": "food_log",
                  "args": {
                    "items": [{
                      "name": "masala dosa",
                      "grams": 220,
                      "calories": 420,
                      "protein_g": 9,
                      "carbs_g": 58,
                      "fat_g": 18,
                      "confidence": "medium"
                    }],
                    "overall_confidence": "medium",
                    "notes": "Potato filling assumed."
                  }
                }
              }]
            }
          }]
        }
        """
        return (200, Data(body.utf8))
    }
    let client = GeminiVisionClient(apiKey: "gkey", session: stubbedSession())
    let resp = try await client.analyze(image: Data([0xff, 0xd8]), prompt: "what's on the plate?")
    #expect(resp.items.count == 1)
    #expect(resp.items[0].name == "masala dosa")
    #expect(resp.items[0].calories == 420)
    #expect(resp.overallConfidence == .medium)
    #expect(resp.notes == "Potato filling assumed.")
}

@Test func geminiRequestKeyGoesInQueryString() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"food_log","args":{"items":[],"overall_confidence":"low"}}}]}}]}"#
        return (200, Data(body.utf8))
    }
    let client = GeminiVisionClient(apiKey: "gk-secret", session: stubbedSession())
    _ = try? await client.analyze(image: Data([0xff]), prompt: "hi")
    let req = StubURLProtocol.lastRequest
    // Key goes in query param `?key=`, NOT a header.
    #expect(req?.url?.absoluteString.contains("key=gk-secret") == true)
    #expect(req?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(req?.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(req?.httpMethod == "POST")
}

@Test func gemini401Or403MapsToUnauthorized() async throws {
    // Gemini signals a bad key with 403, not 401 — the client normalizes.
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        (403, Data(#"{"error":{"code":403,"message":"API key not valid","status":"PERMISSION_DENIED"}}"#.utf8))
    }
    let client = GeminiVisionClient(apiKey: "bad", session: stubbedSession())
    await #expect(throws: CloudVisionError.unauthorized) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func gemini404WithModelNotFoundMapsToProviderError() async throws {
    // Exactly the response seen for `gemini-1.5-flash` on 2026-04-21 —
    // users switching models via a future override need the real reason.
    StubURLProtocol.reset()
    let body = #"{"error":{"code":404,"message":"models/gemini-1.5-flash is not found for API version v1beta","status":"NOT_FOUND"}}"#
    StubURLProtocol.responder = { _ in (404, Data(body.utf8)) }
    let client = GeminiVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.providerError(
        status: 404,
        message: "models/gemini-1.5-flash is not found for API version v1beta"
    )) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func geminiMissingFunctionCallMapsToMalformedPayload() async throws {
    // Gemini sometimes returns `content.parts[].text` only (ignored tool
    // config) or no `functionCall` entry at all — treat as malformed so the
    // user sees a clear error instead of a silent empty result.
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in
        let body = #"{"candidates":[{"content":{"parts":[{"text":"I can't identify that image."}]}}]}"#
        return (200, Data(body.utf8))
    }
    let client = GeminiVisionClient(apiKey: "good", session: stubbedSession())
    await #expect(throws: CloudVisionError.malformedPayload) {
        try await client.analyze(image: Data([0xff]), prompt: "x")
    }
}

@Test func geminiBodyForcesFoodLogFunctionCall() throws {
    let data = try GeminiVisionClient.body(
        image: Data([0x01, 0x02, 0x03]),
        prompt: "log this"
    )
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    // Function declaration
    let tools = json?["tools"] as? [[String: Any]]
    let decls = tools?.first?["functionDeclarations"] as? [[String: Any]]
    #expect(decls?.first?["name"] as? String == "food_log")
    // Forced call mode
    let toolConfig = json?["toolConfig"] as? [String: Any]
    let fcc = toolConfig?["functionCallingConfig"] as? [String: Any]
    #expect(fcc?["mode"] as? String == "ANY")
    #expect(fcc?["allowedFunctionNames"] as? [String] == ["food_log"])
    // Inline image
    let contents = json?["contents"] as? [[String: Any]]
    let parts = contents?.first?["parts"] as? [[String: Any]]
    let inline = parts?.first(where: { $0["inline_data"] != nil })?["inline_data"] as? [String: Any]
    #expect(inline?["mime_type"] as? String == "image/jpeg")
    #expect(inline?["data"] as? String == Data([0x01, 0x02, 0x03]).base64EncodedString())
}
