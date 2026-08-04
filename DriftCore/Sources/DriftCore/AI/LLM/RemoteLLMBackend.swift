import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - HTTP Session Protocol (injectable for testing)

/// Minimal URLSession interface needed by RemoteLLMBackend. URLSession conforms
/// automatically via extension below — tests can supply a mock.
public protocol HTTPDataSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

#if canImport(FoundationNetworking)
// FoundationNetworking's URLSession has no async `data(for:)` — bridge the
// completion-handler API so the conformance holds off-Darwin.
extension URLSession: HTTPDataSession {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}
#else
extension URLSession: HTTPDataSession {}
#endif

// MARK: - Remote Backend Error

/// Categorized errors from the remote backend so the chat layer can decide
/// whether to auto-fallback to local (transient) or surface explicitly to the
/// user (auth / rate-limit / quota — they need to act). #515 Q7.
public enum RemoteBackendError: Error, Sendable, Equatable {
    case auth                // 401/403 — bad/missing key
    case rateLimited         // 429
    case quotaExceeded       // 402 — payment required
    case transient(Int)      // 5xx or network — fallback OK
    case malformed           // Couldn't parse response

    /// True when the chat layer can quietly retry the same turn against the
    /// local backend. Auth / rate / quota all need the user to act, so they
    /// stay false. Photo turns OVERRIDE this to false at the call site —
    /// local has no vision capability. #515 Q7.
    public var isFallbackable: Bool {
        switch self {
        case .transient, .malformed: return true
        case .auth, .rateLimited, .quotaExceeded: return false
        }
    }

    /// Short user-facing message for the explicit-error path. The chat
    /// layer pairs this with a retry CTA. Kept terse — full details (HTTP
    /// status etc.) go to logs, not the chat bubble.
    public var userFacingMessage: String {
        switch self {
        case .auth: return "Drift Coach's cloud brain couldn't authenticate. Switch to on-device, or try again later."
        case .rateLimited: return "Provider is throttling. Wait a minute and tap retry."
        case .quotaExceeded: return "Provider rejected the request — credit balance may be low."
        case .transient: return "Couldn't reach the provider. Tap retry, or switch to on-device."
        case .malformed: return "Provider returned a response Drift couldn't read. Try again."
        }
    }
}

// MARK: - Remote LLM Backend

/// AIBackend backed by Anthropic / OpenAI / Gemini via HTTP. Privacy-surfaced:
/// any call from this backend exits the device. API key is injected by the
/// caller — the iOS app reads it from Keychain; DriftCore itself does not
/// touch Keychain.
///
/// Tool calling: supports BOTH native function-calling (when tool_use /
/// function_call blocks arrive) AND text-JSON fallback (the system prompt
/// instructs cloud LLMs to emit Drift's `{"tool":"...", "key":"val"}` shape).
/// IntentClassifier.parseResponse consumes either uniformly. #515.
public final class RemoteLLMBackend: AIBackend, @unchecked Sendable {

    // MARK: - Provider

    public enum Provider: String, Sendable, CaseIterable {
        case anthropic
        case openai
        case gemini
        /// Nebius AI Studio — OpenAI-compatible inference for open-weight models
        /// (Qwen, Llama, DeepSeek, …). Used by Drift Coach with a team key from
        /// `AppConfig`, NOT user BYOK. Reuses the OpenAI request shape + SSE
        /// parser against the Nebius base URL.
        case nebius

        /// OpenAI-compatible chat-completions base URL for this provider, or nil
        /// for providers with a bespoke API (Anthropic/Gemini build their own URL).
        var openAICompatibleBaseURL: String? {
            switch self {
            case .openai: return "https://api.openai.com/v1"
            case .nebius: return "https://api.studio.nebius.ai/v1"
            case .anthropic, .gemini: return nil
            }
        }
    }

    enum BackendError: Error {
        case invalidURL
    }

    // MARK: - Properties

    public let provider: Provider
    public let modelID: String
    private let apiKey: String?
    let session: any HTTPDataSession

    /// Wall-clock cap on a single in-flight turn. The chat spinner can never
    /// outlast this — a stalled provider surfaces a fallbackable error instead
    /// of an indefinite wait. Enforced two ways: as the `URLRequest` transport
    /// timeout AND as an app-level race in `dataWithTimeout` (so it fires even
    /// for an injected mock session that bypasses URLSession's own timeout). #890
    let requestTimeout: TimeInterval

    /// Last error from a call, in the categorized form. Reset on each call.
    /// Surfaced via `lastErrorBox` actor so callers can read it after the
    /// non-throwing protocol method returns. nil = success.
    private let errorBox = ErrorBox()
    public var lastError: RemoteBackendError? { errorBox.value }

    public var isLoaded: Bool { apiKey != nil }
    public var supportsVision: Bool {
        // All three providers support vision via Photo Log; the chat path's
        // photo turns reuse the same key. Reported true so propose_meal flows
        // can be gated correctly.
        true
    }

    // MARK: - Init

    public init(
        provider: Provider,
        modelID: String,
        apiKey: String?,
        session: any HTTPDataSession = DriftPlatform.httpSession,
        requestTimeout: TimeInterval = 60
    ) {
        self.provider = provider
        self.modelID = modelID
        self.apiKey = apiKey
        self.session = session
        self.requestTimeout = requestTimeout
    }

    // MARK: - AIBackend

    public func load() async throws {}
    public func unload() {}

    public func respond(to prompt: String, systemPrompt: String) async -> String {
        await respondStreaming(to: prompt, systemPrompt: systemPrompt, onToken: { _ in })
    }

    /// Native function-calling variant: ships `toolsJSON` (a JSON-array string of
    /// OpenAI tool schemas) in the request so the model returns structured
    /// tool_calls, which the SSE parser normalizes to Drift's `{"tool":...}`
    /// shape. Only the OpenAI-compatible providers (.openai/.nebius) act on it;
    /// others ignore it (still prose-routed). #coach-agent-loop.
    public func respond(to prompt: String, systemPrompt: String, toolsJSON: String) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: nil, systemPrompt: systemPrompt, toolsJSON: toolsJSON, onToken: { _ in })
    }

    /// Text variant with per-request extraction overrides (mirrors the photo
    /// variant): structured-extraction turns pass `CloudExtractionPolicy`
    /// budgets instead of inheriting chat's 512-token / default-temperature /
    /// 60s economics. No parameter defaults — callers state their budgets, and
    /// the compiler keeps this unambiguous with the protocol `respond`.
    public func respond(to prompt: String, systemPrompt: String, toolsJSON: String?,
                        maxTokens: Int, temperature: Double?, timeout: TimeInterval?) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: nil, systemPrompt: systemPrompt,
                                   toolsJSON: toolsJSON, maxTokens: maxTokens,
                                   timeout: timeout, temperature: temperature, onToken: { _ in })
    }

    public func respondStreaming(
        to prompt: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: nil, systemPrompt: systemPrompt, onToken: onToken)
    }

    /// Photo-capable variant. Embeds `imageData` (JPEG bytes) in the user
    /// content block alongside the text prompt, per each provider's vision API.
    /// `maxTokens`/`timeout` override the chat defaults (512 / requestTimeout)
    /// for structured-extraction turns: a full-page workout scan emits JSON far
    /// beyond 512 tokens, and a 72B vision model reading a dense handwritten
    /// page overruns the 60s chat deadline — truncation or timeout both
    /// surfaced as a bogus "couldn't reach the cloud" (field bug, build 358).
    public func respondStreamingWithPhoto(
        to prompt: String,
        imageData: Data,
        systemPrompt: String,
        visionModelID: String? = nil,
        maxTokens: Int = 512,
        timeout: TimeInterval? = nil,
        temperature: Double? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, visionModelID: visionModelID, maxTokens: maxTokens, timeout: timeout, temperature: temperature, onToken: onToken)
    }

    private func respondStreamingCore(
        prompt: String,
        imageData: Data?,
        systemPrompt: String,
        toolsJSON: String? = nil,
        visionModelID: String? = nil,
        maxTokens: Int = 512,
        timeout: TimeInterval? = nil,
        temperature: Double? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        // Per-device daily budget (#1113) — every remote call funnels through
        // here, so this one gate covers chat, describe, exercise text, and
        // photo scans on both platforms. Denial = .rateLimited: chat surfaces
        // its limit message; extraction ladders fall back offline. Bypassed
        // under XCTest — the Tier-3/4 evals fire hundreds of legitimate real
        // calls per run and must never trip a per-device cap.
        if NSClassFromString("XCTestCase") == nil {
            let estimated = systemPrompt.count + prompt.count
                + (imageData != nil ? CloudUsageThrottle.photoCharEquivalent : 0)
            guard CloudUsageThrottle.permit(estimatedChars: estimated) else {
                errorBox.value = .rateLimited
                Log.app.error("RemoteLLMBackend: daily cloud budget reached — call denied (#1113)")
                return ""
            }
        }
        let reply = await respondStreamingCoreUnmetered(
            prompt: prompt, imageData: imageData, systemPrompt: systemPrompt,
            toolsJSON: toolsJSON, visionModelID: visionModelID, maxTokens: maxTokens,
            timeout: timeout, temperature: temperature, onToken: onToken)
        CloudUsageThrottle.record(chars: reply.count)
        return reply
    }

    private func respondStreamingCoreUnmetered(
        prompt: String,
        imageData: Data?,
        systemPrompt: String,
        toolsJSON: String?,
        visionModelID: String?,
        maxTokens: Int,
        timeout: TimeInterval?,
        temperature: Double?,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        errorBox.value = nil
        let effectiveTimeout = timeout ?? requestTimeout
        guard let key = apiKey else {
            errorBox.value = .auth
            return ""
        }
        do {
            // #1177: image turns on the BUFFERED transport ask for a
            // non-streaming completion. Requesting SSE and then buffering the
            // whole body is the worst of both worlds on Android: the provider
            // flushes the role-announcement chunk instantly and then goes
            // BYTE-SILENT for the whole vision read, and an idle-looking
            // connection reaped mid-stream comes back as a clean HTTP 200
            // carrying only that first chunk — no error, nothing to retry, a
            // silent dead-end. `stream:false` is one round trip with a real
            // Content-Length, so there is no held-open silent window to reap,
            // and a genuine cut now throws instead of masquerading as success.
            // Nothing is lost: the buffered path never streamed anyway (it
            // parses the finished body and fires onToken at the end).
            // Mirrors the Darwin/URLSession guard below — Darwin keeps true
            // streaming, and buffered TEXT turns (short, proven working) stay
            // on SSE.
            #if canImport(Darwin)
            let bufferedTransport = (session as? URLSession) == nil
            #else
            let bufferedTransport = true
            #endif
            var request = try buildRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: key, toolsJSON: toolsJSON, visionModelID: visionModelID, maxTokens: maxTokens, temperature: temperature, stream: !(bufferedTransport && imageData != nil))
            request.timeoutInterval = effectiveTimeout

            // True token streaming via URLSession.bytes — tokens reach the UI as
            // generated instead of waiting for the full response. Vision turns
            // stream too (2026-07-22): the buffered path left the connection
            // BYTE-SILENT for the whole 40-115s model read, and cellular
            // NATs/middleboxes reap idle-looking connections — big workout
            // scans died on-device while the same call succeeded on Wi-Fi.
            // Streaming keeps packets flowing once generation starts, and makes
            // first-token progress real. Test mocks (non-URLSession) fall back
            // to buffered. (#944)
            //
            // #1133: gated to Darwin. `.bytes(for:)` is a Darwin-Foundation API;
            // the non-Darwin (Android) runtime's swift-corelibs-foundation
            // `URLSession.data(for:)` parks NON-cancellably, and routing it
            // through streamWithBytes' task-group traps every deadline — the 60s
            // timeout child can't return until the parked network child drains —
            // so Coach spun on "Looking that up…" forever. Android falls through
            // to the buffered dataWithTimeout + synchronous parseResponse below:
            // the exact path every non-URLSession mock-session test exercises, so
            // parse/delivery is already proven.
            #if canImport(Darwin)
            if let urlSession = session as? URLSession {
                return await streamWithBytes(urlSession: urlSession, request: request, timeout: effectiveTimeout, onToken: onToken)
            }
            #endif

            let (data, response) = try await dataWithTimeout(for: request, timeout: effectiveTimeout)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errorBox.value = categorize(status: http.statusCode)
                Log.app.error("RemoteLLMBackend: HTTP \(http.statusCode) (\(self.provider.rawValue))")
                return ""
            }
            return parseResponse(data: data, onToken: onToken)
        } catch {
            errorBox.value = .transient(0)
            Log.app.error("RemoteLLMBackend: \(error)")
            return ""
        }
    }

    #if canImport(Darwin)
    /// Streams the SSE response line-by-line via URLSession.bytes so onToken
    /// fires as each token arrives rather than after the entire generation.
    /// Darwin-only: `.bytes(for:)` is a Darwin-Foundation API, and #1133 routes
    /// the non-Darwin (Android) runtime through the buffered path in
    /// `respondStreamingCoreUnmetered` — so this is unreachable off-Darwin.
    private func streamWithBytes(
        urlSession: URLSession,
        request: URLRequest,
        timeout: TimeInterval,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { [provider] in
                    let (asyncBytes, response) = try await urlSession.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw RemoteStatusError(status: http.statusCode)
                    }
                    let lines = asyncBytes.lines
                    switch provider {
                    case .openai, .nebius:
                        return try await OpenAISSEParser.parseStream(lines, onToken: onToken)
                    case .anthropic:
                        return try await AnthropicSSEParser.parseStream(lines, onToken: onToken)
                    case .gemini:
                        return try await GeminiSSEParser.parseStream(lines, onToken: onToken)
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw RemoteTimeoutError()
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch let e as RemoteStatusError {
            errorBox.value = categorize(status: e.status)
            Log.app.error("RemoteLLMBackend: HTTP \(e.status) streaming (\(self.provider.rawValue))")
        } catch {
            errorBox.value = .transient(0)
            Log.app.error("RemoteLLMBackend: \(error) streaming (\(self.provider.rawValue))")
        }
        return ""
    }
    #endif

    /// Error thrown when the in-flight provider call exceeds `requestTimeout`.
    /// Flows through `respondStreamingCore`'s catch → `.transient(0)`, so the
    /// chat layer treats a hang exactly like any other transient network fault
    /// (fallbackable — retry or switch to on-device). #890
    private struct RemoteTimeoutError: Error {}

    /// Carries an HTTP status code out of `streamWithBytes` so the caller can
    /// categorize it the same way the buffered path does.
    private struct RemoteStatusError: Error { let status: Int }

    /// Races the provider call against `requestTimeout`. Whichever finishes
    /// first wins; the loser is cancelled. Enforcing the deadline HERE — not
    /// only via `URLRequest.timeoutInterval` — guarantees a bounded wait even
    /// when a custom/mock `HTTPDataSession` is injected (URLSession's own
    /// timeout never runs in that path). The in-flight chat spinner can never
    /// hang indefinitely. #890
    private func dataWithTimeout(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        #if canImport(Darwin)
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.session.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RemoteTimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        #else
        // #1133: a withTaskGroup racing Task.sleep never resolves on the
        // Android Swift-concurrency runtime even after the real child
        // completes — proved by a 10s classifyFull timeout not firing after
        // 5+ minutes. The OkHttp facade (AndroidHTTPSession -> HttpFacade,
        // #1136) already enforces call/read/write timeouts, so the call is
        // bounded without a Swift-side race. Await directly.
        try await session.data(for: request)
        #endif
    }

    private func categorize(status: Int) -> RemoteBackendError {
        switch status {
        case 401, 403: return .auth
        case 402:      return .quotaExceeded
        case 429:      return .rateLimited
        case 500...599: return .transient(status)
        default:       return .transient(status)
        }
    }

    // MARK: - Request Building

    private func buildRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String, toolsJSON: String? = nil, visionModelID: String? = nil, maxTokens: Int = 512, temperature: Double? = nil, stream: Bool = true) throws -> URLRequest {
        switch provider {
        case .anthropic:
            return try buildAnthropicRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey, maxTokens: maxTokens, temperature: temperature)
        case .openai, .nebius:
            guard let baseURL = provider.openAICompatibleBaseURL else { throw BackendError.invalidURL }
            // Image turns need a vision model — the text coach model (Qwen3) 400s
            // on images. Swap to visionModelID only when an image is attached.
            let model = (imageData != nil) ? (visionModelID ?? modelID) : modelID
            return try buildOpenAICompatibleRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey, baseURL: baseURL, model: model, toolsJSON: toolsJSON, maxTokens: maxTokens, temperature: temperature, stream: stream)
        case .gemini:
            return try buildGeminiRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey)
        }
    }

    private func buildAnthropicRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String, maxTokens: Int = 512, temperature: Double? = nil) throws -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw BackendError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let userContent: Any
        if let jpeg = imageData {
            userContent = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ["type": "text", "text": prompt]
            ] as [Any]
        } else {
            userContent = prompt
        }

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userContent]]
        ]
        if let temperature { body["temperature"] = temperature }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Build an OpenAI-compatible `/chat/completions` request. Shared by `.openai`
    /// (api.openai.com) and `.nebius` (api.studio.nebius.ai) — identical request
    /// body + SSE shape, only the base URL differs.
    private func buildOpenAICompatibleRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String, baseURL: String, model: String, toolsJSON: String? = nil, maxTokens: Int = 512, temperature: Double? = nil, stream: Bool = true) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw BackendError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let userContent: Any
        if let jpeg = imageData {
            let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            userContent = [
                ["type": "image_url", "image_url": ["url": dataURL]],
                ["type": "text", "text": prompt]
            ] as [Any]
        } else {
            userContent = prompt
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
        // Structured-extraction turns (workout scan) pin temperature 0 for
        // deterministic reads; chat turns leave it unset (provider default).
        if let temperature { body["temperature"] = temperature }
        // Native function-calling: splice the tools schema array (passed as a
        // Sendable JSON string) so the model returns structured tool_calls.
        if let toolsJSON,
           let data = toolsJSON.data(using: .utf8),
           let toolsArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
           !toolsArray.isEmpty {
            body["tools"] = toolsArray
            body["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func buildGeminiRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw BackendError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = []
        if let jpeg = imageData {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": prompt])

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generation_config": ["max_output_tokens": 512]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, onToken: @escaping @Sendable (String) -> Void) -> String {
        switch provider {
        case .anthropic:       return AnthropicSSEParser.parse(data: data, onToken: onToken)
        case .openai, .nebius: return OpenAISSEParser.parse(data: data, onToken: onToken)
        case .gemini:          return GeminiSSEParser.parse(data: data, onToken: onToken)
        }
    }
}

// MARK: - ErrorBox

/// Atomic single-cell box for `lastError` so the value-type `RemoteLLMBackend`
/// stays @unchecked Sendable without exposing a mutable property reference.
private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: RemoteBackendError?
    var value: RemoteBackendError? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

// MARK: - SSE Helpers

/// Iterates over `data: …` payload lines in an SSE buffer, ignoring
/// `[DONE]` markers, blank lines, and `event:` headers. Yields the parsed
/// JSON object for each event.
private enum SSE {
    static func eachJSONEvent(_ raw: String, _ handler: ([String: Any]) -> Void) {
        for line in raw.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            guard jsonStr != "[DONE]",
                  let jData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jData) as? [String: Any]
            else { continue }
            handler(event)
        }
    }

    /// Merge a tool name + JSON-shaped arguments into Drift's flat
    /// `{"tool":"name","key":"val"}` format that IntentClassifier expects.
    /// Accepts arguments as either a parsed dict or a JSON string.
    static func formatToolCall(name: String, arguments: Any) -> String {
        guard !name.isEmpty else { return "" }
        var params: [String: Any] = [:]
        if let dict = arguments as? [String: Any] {
            params = dict
        } else if let str = arguments as? String,
                  let data = str.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            params = parsed
        }
        params["tool"] = name
        guard let merged = try? JSONSerialization.data(withJSONObject: params, options: .sortedKeys),
              let str = String(data: merged, encoding: .utf8)
        else { return "{\"tool\":\"\(name)\"}" }
        return str
    }
}

// MARK: - Anthropic SSE Parser

/// Parses Anthropic streaming SSE bytes into a unified string result.
/// Two response modes:
/// - text:     concatenated text_delta tokens, delivered to onToken as they arrive.
/// - tool_use: input JSON accumulated from input_json_delta events, then merged
///             with the tool name into Drift's {"tool":"...","key":"val"} format
///             so IntentClassifier.parseResponse can consume it directly.
enum AnthropicSSEParser {

    struct Block {
        var type: String = ""       // "text" or "tool_use"
        var toolName: String = ""
        var textBuffer: String = ""
        var toolInputBuffer: String = ""
    }

    static func parse(data: Data, onToken: @escaping @Sendable (String) -> Void) -> String {
        guard let raw = String(data: data, encoding: .utf8) else { return "" }
        var blocks: [Int: Block] = [:]   // keyed by content_block index

        SSE.eachJSONEvent(raw) { event in
            switch event["type"] as? String ?? "" {

            case "content_block_start":
                let index = event["index"] as? Int ?? 0
                if let cb = event["content_block"] as? [String: Any] {
                    var block = Block()
                    block.type = cb["type"] as? String ?? ""
                    block.toolName = cb["name"] as? String ?? ""
                    blocks[index] = block
                }

            case "content_block_delta":
                let index = event["index"] as? Int ?? 0
                guard let delta = event["delta"] as? [String: Any] else { return }
                let deltaType = delta["type"] as? String ?? ""
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    onToken(text)
                    blocks[index, default: Block()].textBuffer += text
                } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                    blocks[index, default: Block()].toolInputBuffer += partial
                }

            default:
                break
            }
        }

        // Prefer first tool_use block (by SSE index); fall back to concatenated text in index order.
        if let toolEntry = blocks.filter({ $0.value.type == "tool_use" }).min(by: { $0.key < $1.key }) {
            return SSE.formatToolCall(name: toolEntry.value.toolName,
                                       arguments: toolEntry.value.toolInputBuffer)
        }

        return blocks.sorted(by: { $0.key < $1.key })
            .filter { $0.value.type == "text" }
            .map { $0.value.textBuffer }
            .joined()
    }

    static func parseStream<Lines: AsyncSequence>(
        _ lines: Lines, onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String where Lines.Element == String {
        var blocks: [Int: Block] = [:]
        for try await line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            guard jsonStr != "[DONE]",
                  let jData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jData) as? [String: Any] else { continue }
            switch event["type"] as? String ?? "" {
            case "content_block_start":
                let index = event["index"] as? Int ?? 0
                if let cb = event["content_block"] as? [String: Any] {
                    var block = Block()
                    block.type = cb["type"] as? String ?? ""
                    block.toolName = cb["name"] as? String ?? ""
                    blocks[index] = block
                }
            case "content_block_delta":
                let index = event["index"] as? Int ?? 0
                guard let delta = event["delta"] as? [String: Any] else { continue }
                let dType = delta["type"] as? String ?? ""
                if dType == "text_delta", let text = delta["text"] as? String {
                    onToken(text); blocks[index, default: Block()].textBuffer += text
                } else if dType == "input_json_delta", let partial = delta["partial_json"] as? String {
                    blocks[index, default: Block()].toolInputBuffer += partial
                }
            default: break
            }
        }
        if let toolEntry = blocks.filter({ $0.value.type == "tool_use" }).min(by: { $0.key < $1.key }) {
            return SSE.formatToolCall(name: toolEntry.value.toolName, arguments: toolEntry.value.toolInputBuffer)
        }
        return blocks.sorted(by: { $0.key < $1.key }).filter { $0.value.type == "text" }.map { $0.value.textBuffer }.joined()
    }
}

// MARK: - OpenAI SSE Parser

/// Parses OpenAI chat-completions streaming SSE bytes.
/// Two response modes:
/// - content:   `choices[0].delta.content` text tokens — delivered to onToken.
/// - tool_calls: `choices[0].delta.tool_calls[].function.name + arguments` —
///   accumulated and merged with the function name into Drift's flat JSON.
/// OpenAI returns multiple tool_calls in a single response; v1 picks the first
/// (matches Anthropic) — parallel tool calls are out of scope for this issue.
enum OpenAISSEParser {

    struct ToolBuf {
        var name: String = ""
        var arguments: String = ""
    }

    static func parse(data: Data, onToken: @escaping @Sendable (String) -> Void) -> String {
        // A `stream:false` turn (#1177 — the Android buffered transport's image
        // path) answers with ONE `chat.completion` object instead of `data: …`
        // events. Detect it by decoding the whole body as JSON: every SSE body
        // starts with `data: `, so this fails cleanly there and falls through
        // to the event loop below — no string sniffing, no mode flag to thread.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let completion = parseNonStreaming(object, onToken: onToken) {
            return completion
        }

        guard let raw = String(data: data, encoding: .utf8) else { return "" }
        var text = ""
        var tools: [Int: ToolBuf] = [:]

        SSE.eachJSONEvent(raw) { event in
            guard let choices = event["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else { return }

            if let content = delta["content"] as? String, !content.isEmpty {
                onToken(content)
                text += content
            }

            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let index = call["index"] as? Int ?? 0
                    var buf = tools[index] ?? ToolBuf()
                    if let fn = call["function"] as? [String: Any] {
                        if let name = fn["name"] as? String, !name.isEmpty { buf.name = name }
                        if let args = fn["arguments"] as? String { buf.arguments += args }
                    }
                    tools[index] = buf
                }
            }
        }

        if let firstTool = tools.min(by: { $0.key < $1.key })?.value, !firstTool.name.isEmpty {
            return SSE.formatToolCall(name: firstTool.name, arguments: firstTool.arguments)
        }
        return text
    }

    /// Decodes a non-streaming `chat.completion` body: `choices[0].message`
    /// carries the finished reply in one shot instead of `delta` fragments.
    /// Returns nil when the object isn't a completion (an error payload, or an
    /// SSE body that happened to decode) so the caller falls back to the SSE
    /// path. Tool calls win over content, matching the streaming parser.
    private static func parseNonStreaming(_ object: [String: Any], onToken: @escaping @Sendable (String) -> Void) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }

        if let call = (message["tool_calls"] as? [[String: Any]])?.first,
           let function = call["function"] as? [String: Any],
           let name = function["name"] as? String, !name.isEmpty {
            return SSE.formatToolCall(name: name, arguments: function["arguments"] ?? [:])
        }

        guard let content = message["content"] as? String, !content.isEmpty else { return "" }
        onToken(content)
        return content
    }

    static func parseStream<Lines: AsyncSequence>(
        _ lines: Lines, onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String where Lines.Element == String {
        var text = ""
        var tools: [Int: ToolBuf] = [:]
        for try await line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            guard jsonStr != "[DONE]",
                  let jData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jData) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else { continue }
            if let content = delta["content"] as? String, !content.isEmpty {
                onToken(content); text += content
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let idx = call["index"] as? Int ?? 0
                    var buf = tools[idx] ?? ToolBuf()
                    if let fn = call["function"] as? [String: Any] {
                        if let name = fn["name"] as? String, !name.isEmpty { buf.name = name }
                        if let args = fn["arguments"] as? String { buf.arguments += args }
                    }
                    tools[idx] = buf
                }
            }
        }
        if let firstTool = tools.min(by: { $0.key < $1.key })?.value, !firstTool.name.isEmpty {
            return SSE.formatToolCall(name: firstTool.name, arguments: firstTool.arguments)
        }
        return text
    }
}

// MARK: - Gemini SSE Parser

/// Parses Gemini `streamGenerateContent?alt=sse` payloads.
/// Two response modes:
/// - text parts:  `candidates[0].content.parts[].text` — concatenated and streamed.
/// - functionCall:`candidates[0].content.parts[].functionCall.name + args`
///   merged into Drift's flat JSON tool-call shape.
enum GeminiSSEParser {

    static func parse(data: Data, onToken: @escaping @Sendable (String) -> Void) -> String {
        guard let raw = String(data: data, encoding: .utf8) else { return "" }
        var text = ""
        var toolName = ""
        var toolArgs: [String: Any] = [:]

        SSE.eachJSONEvent(raw) { event in
            guard let candidates = event["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return }
            for part in parts {
                if let t = part["text"] as? String, !t.isEmpty {
                    onToken(t)
                    text += t
                }
                if let fn = part["functionCall"] as? [String: Any] {
                    if let n = fn["name"] as? String, !n.isEmpty { toolName = n }
                    if let args = fn["args"] as? [String: Any] {
                        for (k, v) in args { toolArgs[k] = v }
                    }
                }
            }
        }

        if !toolName.isEmpty {
            return SSE.formatToolCall(name: toolName, arguments: toolArgs)
        }
        return text
    }

    static func parseStream<Lines: AsyncSequence>(
        _ lines: Lines, onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String where Lines.Element == String {
        var text = ""
        var toolName = ""
        var toolArgs: [String: Any] = [:]
        for try await line in lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            guard jsonStr != "[DONE]",
                  let jData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jData) as? [String: Any],
                  let candidates = event["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let t = part["text"] as? String, !t.isEmpty { onToken(t); text += t }
                if let fn = part["functionCall"] as? [String: Any] {
                    if let n = fn["name"] as? String, !n.isEmpty { toolName = n }
                    if let args = fn["args"] as? [String: Any] { for (k, v) in args { toolArgs[k] = v } }
                }
            }
        }
        if !toolName.isEmpty { return SSE.formatToolCall(name: toolName, arguments: toolArgs) }
        return text
    }
}
