import Foundation
@testable import DriftCore
import Testing

// MARK: - Mock HTTP Session

/// Returns pre-canned Data for every request. No network I/O.
struct MockHTTPSession: HTTPDataSession, Sendable {
    let responseData: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

struct MockHTTPSessionError: HTTPDataSession, Sendable {
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

// MARK: - Canned SSE Fixtures

private enum SSEFixture {
    /// Anthropic streaming SSE with one text content block delivering "Hello world".
    static let textResponse = Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet-4-6","content":[],"stop_reason":null,"usage":{"input_tokens":10,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}

        event: message_stop
        data: {"type":"message_stop"}

        """.utf8)

    /// Anthropic streaming SSE with a tool_use block for log_food(name=eggs, servings=2).
    static let toolCallResponse = Data("""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_02","type":"message","role":"assistant","model":"claude-sonnet-4-6","content":[],"stop_reason":null,"usage":{"input_tokens":20,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01","name":"log_food","input":{}}}

        event: ping
        data: {"type":"ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"name\\":"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"eggs\\","}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"servings\\":\\"2\\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":18}}

        event: message_stop
        data: {"type":"message_stop"}

        """.utf8)
}

// MARK: - Request-Capturing Session

private final class RequestBox: @unchecked Sendable { var request: URLRequest? }

private struct CapturingSession: HTTPDataSession, Sendable {
    let box: RequestBox
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        box.request = request
        let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), r)
    }
}

// MARK: - RemoteLLMBackend Tests

/// Tier-0: no real network, no model. MockHTTPSession returns pre-canned SSE.
struct RemoteLLMBackendTests {

    // MARK: - Init / isLoaded

    @Test func isLoadedWhenAPIKeyProvided() {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: Data())
        )
        #expect(backend.isLoaded == true)
    }

    @Test func notLoadedWhenAPIKeyNil() {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: nil, session: MockHTTPSession(responseData: Data())
        )
        #expect(backend.isLoaded == false)
    }

    @Test func loadAndUnloadAreNoOps() async throws {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: Data())
        )
        try await backend.load()
        backend.unload()
        #expect(backend.isLoaded == true)
    }

    @Test func supportsVisionIsTrue() {
        // All three providers (Anthropic / OpenAI / Gemini) support vision via
        // the same Photo Log key. The chat layer reads supportsVision to gate
        // photo-attached propose_meal flows. #515.
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: Data())
        )
        #expect(backend.supportsVision == true)
    }

    // MARK: - Request Construction

    @Test func anthropicRequestHasCorrectHeaders() async throws {
        let box = RequestBox()
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test-key", session: CapturingSession(box: box)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        let req = try #require(box.request)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test-key")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.url?.host == "api.anthropic.com")
    }

    @Test func openAIRequestHasBearerToken() async throws {
        let box = RequestBox()
        let backend = RemoteLLMBackend(
            provider: .openai, modelID: "gpt-4o",
            apiKey: "sk-openai", session: CapturingSession(box: box)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        let req = try #require(box.request)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openai")
        #expect(req.url?.host == "api.openai.com")
    }

    // MARK: - Missing API Key

    @Test func returnsEmptyWhenNoAPIKey() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: nil, session: MockHTTPSession(responseData: SSEFixture.textResponse)
        )
        let result = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(result.isEmpty)
    }

    // MARK: - Text Streaming Round Trip

    @Test func textResponseDelivered() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: SSEFixture.textResponse)
        )
        let result = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(result == "Hello world")
    }

    @Test func textStreamingDeliversTokensIncrementally() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: SSEFixture.textResponse)
        )
        var tokens: [String] = []
        _ = await backend.respondStreaming(to: "hi", systemPrompt: "sys") { token in
            tokens.append(token)
        }
        #expect(tokens == ["Hello", " world"])
    }

    // MARK: - Tool Call Round Trip

    @Test func toolCallSSEReturnsDriftJSON() async throws {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: SSEFixture.toolCallResponse)
        )
        let result = await backend.respond(to: "log 2 eggs", systemPrompt: "sys")
        #expect(!result.isEmpty, "tool_use SSE must produce non-empty output")

        // IntentClassifier must be able to parse the result as a tool call
        let intent = IntentClassifier.parseResponse(result)
        let parsed = try #require(intent)
        #expect(parsed.tool == "log_food")
        #expect(parsed.params["name"] == "eggs")
        #expect(parsed.params["servings"] == "2")
    }

    @Test func toolCallStreamingDeliversNoSpuriousTokens() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: SSEFixture.toolCallResponse)
        )
        var tokens: [String] = []
        _ = await backend.respondStreaming(to: "log 2 eggs", systemPrompt: "sys") { token in
            tokens.append(token)
        }
        // tool_use blocks deliver no text tokens — the result is returned as the final string
        #expect(tokens.isEmpty, "tool_use SSE must not deliver spurious text tokens")
    }

    @Test func toolCallResultParsedByIntentClassifierMapResponse() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSession(responseData: SSEFixture.toolCallResponse)
        )
        let result = await backend.respond(to: "log 2 eggs", systemPrompt: "sys")
        let classifyResult = IntentClassifier.mapResponse(result)
        guard case .toolCall(let intent) = classifyResult else {
            Issue.record("Expected toolCall, got \(String(describing: classifyResult))")
            return
        }
        #expect(intent.tool == "log_food")
        #expect(intent.params["name"] == "eggs")
    }

    // MARK: - HTTP Error Handling

    @Test func httpErrorReturnsEmpty() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSessionError(statusCode: 429)
        )
        let result = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(result.isEmpty)
    }

    // MARK: - Preferences

    @Test func useRemoteModelOnWiFiRoundTrips() {
        let original = Preferences.useRemoteModelOnWiFi
        defer { Preferences.useRemoteModelOnWiFi = original }
        Preferences.useRemoteModelOnWiFi = true
        #expect(Preferences.useRemoteModelOnWiFi == true)
        Preferences.useRemoteModelOnWiFi = false
        #expect(Preferences.useRemoteModelOnWiFi == false)
    }

    /// Single test covers both the round-trip and the default — Swift Testing
    /// runs `@Test` functions in parallel and the two cases share the same
    /// UserDefaults key, so split tests would race. Privacy-first tenet
    /// pins the default to local; remote requires opt-in.
    @Test func preferredAIBackendRoundTripsAndDefaultsToLocal() {
        let original = Preferences.preferredAIBackend
        defer { Preferences.preferredAIBackend = original }

        // Default branch: no stored value → foundationModels
        // (2026-05-19 LLM-swap migration: was .llamaCpp)
        UserDefaults.standard.removeObject(forKey: "drift_preferred_ai_backend")
        #expect(Preferences.preferredAIBackend == .foundationModels)

        // Round-trip
        Preferences.preferredAIBackend = .remote
        #expect(Preferences.preferredAIBackend == .remote)
        Preferences.preferredAIBackend = .llamaCpp
        #expect(Preferences.preferredAIBackend == .llamaCpp)
    }

    // MARK: - Provider Coverage

    @Test func providerHasAllThreeCases() {
        // Catches accidental enum trims that would silently break a provider.
        let all = RemoteLLMBackend.Provider.allCases
        #expect(all.contains(.anthropic))
        #expect(all.contains(.openai))
        #expect(all.contains(.gemini))
        #expect(all.count == 3)
    }

    @Test func geminiRequestUsesQueryStringAuth() async throws {
        let box = RequestBox()
        let backend = RemoteLLMBackend(
            provider: .gemini, modelID: "gemini-2.5-flash",
            apiKey: "test-gem", session: CapturingSession(box: box)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        let req = try #require(box.request)
        // Gemini auth is query-string ?key=…, not a header
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(req.url?.host == "generativelanguage.googleapis.com")
        #expect(req.url?.query?.contains("key=test-gem") == true)
        #expect(req.url?.query?.contains("alt=sse") == true)
    }

    // MARK: - OpenAI SSE Parsing

    @Test func openAITextSSEParsedAndStreamed() async {
        let sse = Data("""
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: [DONE]

            """.utf8)
        let backend = RemoteLLMBackend(
            provider: .openai, modelID: "gpt-4o",
            apiKey: "sk-test", session: MockHTTPSession(responseData: sse)
        )
        var tokens: [String] = []
        let result = await backend.respondStreaming(to: "hi", systemPrompt: "sys") { tokens.append($0) }
        #expect(result == "Hello world")
        #expect(tokens == ["Hello", " world"])
    }

    @Test func openAIToolCallSSEReturnsDriftJSON() async throws {
        // Two tool_call deltas — first establishes name + opens args, second
        // appends the rest of the args. Mirrors how OpenAI streams in real life.
        let sse = Data("""
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_01","type":"function","function":{"name":"log_food","arguments":"{\\"name\\":"}}]}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"eggs\\",\\"servings\\":\\"2\\"}"}}]}}]}

            data: [DONE]

            """.utf8)
        let backend = RemoteLLMBackend(
            provider: .openai, modelID: "gpt-4o",
            apiKey: "sk-test", session: MockHTTPSession(responseData: sse)
        )
        let result = await backend.respond(to: "log 2 eggs", systemPrompt: "sys")
        #expect(!result.isEmpty)
        let intent = try #require(IntentClassifier.parseResponse(result))
        #expect(intent.tool == "log_food")
        #expect(intent.params["name"] == "eggs")
        #expect(intent.params["servings"] == "2")
    }

    // MARK: - Gemini SSE Parsing

    @Test func geminiTextSSEParsedAndStreamed() async {
        let sse = Data("""
            data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}

            data: {"candidates":[{"content":{"parts":[{"text":" there"}]}}]}

            """.utf8)
        let backend = RemoteLLMBackend(
            provider: .gemini, modelID: "gemini-2.5-flash",
            apiKey: "test-gem", session: MockHTTPSession(responseData: sse)
        )
        var tokens: [String] = []
        let result = await backend.respondStreaming(to: "hi", systemPrompt: "sys") { tokens.append($0) }
        #expect(result == "Hi there")
        #expect(tokens == ["Hi", " there"])
    }

    @Test func geminiFunctionCallSSEReturnsDriftJSON() async throws {
        let sse = Data("""
            data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"log_food","args":{"name":"biryani","servings":"1"}}}]}}]}

            """.utf8)
        let backend = RemoteLLMBackend(
            provider: .gemini, modelID: "gemini-2.5-flash",
            apiKey: "test-gem", session: MockHTTPSession(responseData: sse)
        )
        let result = await backend.respond(to: "had biryani", systemPrompt: "sys")
        let intent = try #require(IntentClassifier.parseResponse(result))
        #expect(intent.tool == "log_food")
        #expect(intent.params["name"] == "biryani")
        #expect(intent.params["servings"] == "1")
    }

    // MARK: - Error Categorization (Q7)

    @Test func authErrorSetsLastError() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSessionError(statusCode: 401)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(backend.lastError == .auth)
        #expect(backend.lastError?.isFallbackable == false)
    }

    @Test func rateLimitErrorSetsLastError() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSessionError(statusCode: 429)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(backend.lastError == .rateLimited)
        #expect(backend.lastError?.isFallbackable == false)
    }

    @Test func quotaExceededErrorSetsLastError() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSessionError(statusCode: 402)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(backend.lastError == .quotaExceeded)
        #expect(backend.lastError?.isFallbackable == false)
    }

    @Test func transientErrorSetsLastErrorFallbackable() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: MockHTTPSessionError(statusCode: 503)
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(backend.lastError == .transient(503))
        #expect(backend.lastError?.isFallbackable == true)
    }

    @Test func missingAPIKeySetsAuthError() async {
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: nil, session: MockHTTPSession(responseData: Data())
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        // Treat nil-key as auth so the chat layer surfaces the same retry CTA
        // as a 401 instead of silently fallback-ing to local.
        #expect(backend.lastError == .auth)
    }

    @Test func successResetsLastError() async {
        let session = MockHTTPSession(responseData: SSEFixture.textResponse)
        let backend = RemoteLLMBackend(
            provider: .anthropic, modelID: "claude-sonnet-4-6",
            apiKey: "sk-test", session: session
        )
        _ = await backend.respond(to: "hi", systemPrompt: "sys")
        #expect(backend.lastError == nil)
    }
}
