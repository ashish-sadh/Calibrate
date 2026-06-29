import Foundation

// MARK: - HTTP Session Protocol (injectable for testing)

/// Minimal URLSession interface needed by RemoteLLMBackend. URLSession conforms
/// automatically via extension below — tests can supply a mock.
public protocol HTTPDataSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataSession {}

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
        session: any HTTPDataSession = URLSession.shared,
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

    public func respondStreaming(
        to prompt: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: nil, systemPrompt: systemPrompt, onToken: onToken)
    }

    /// Photo-capable variant. Embeds `imageData` (JPEG bytes) in the user
    /// content block alongside the text prompt, per each provider's vision API.
    public func respondStreamingWithPhoto(
        to prompt: String,
        imageData: Data,
        systemPrompt: String,
        visionModelID: String? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        await respondStreamingCore(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, visionModelID: visionModelID, onToken: onToken)
    }

    private func respondStreamingCore(
        prompt: String,
        imageData: Data?,
        systemPrompt: String,
        toolsJSON: String? = nil,
        visionModelID: String? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        errorBox.value = nil
        guard let key = apiKey else {
            errorBox.value = .auth
            return ""
        }
        do {
            var request = try buildRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: key, toolsJSON: toolsJSON, visionModelID: visionModelID)
            request.timeoutInterval = requestTimeout
            let (data, response) = try await dataWithTimeout(for: request)
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

    /// Error thrown when the in-flight provider call exceeds `requestTimeout`.
    /// Flows through `respondStreamingCore`'s catch → `.transient(0)`, so the
    /// chat layer treats a hang exactly like any other transient network fault
    /// (fallbackable — retry or switch to on-device). #890
    private struct RemoteTimeoutError: Error {}

    /// Races the provider call against `requestTimeout`. Whichever finishes
    /// first wins; the loser is cancelled. Enforcing the deadline HERE — not
    /// only via `URLRequest.timeoutInterval` — guarantees a bounded wait even
    /// when a custom/mock `HTTPDataSession` is injected (URLSession's own
    /// timeout never runs in that path). The in-flight chat spinner can never
    /// hang indefinitely. #890
    private func dataWithTimeout(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.session.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
                throw RemoteTimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
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

    private func buildRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String, toolsJSON: String? = nil, visionModelID: String? = nil) throws -> URLRequest {
        switch provider {
        case .anthropic:
            return try buildAnthropicRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey)
        case .openai, .nebius:
            guard let baseURL = provider.openAICompatibleBaseURL else { throw BackendError.invalidURL }
            // Image turns need a vision model — the text coach model (Qwen3) 400s
            // on images. Swap to visionModelID only when an image is attached.
            let model = (imageData != nil) ? (visionModelID ?? modelID) : modelID
            return try buildOpenAICompatibleRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey, baseURL: baseURL, model: model, toolsJSON: toolsJSON)
        case .gemini:
            return try buildGeminiRequest(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt, apiKey: apiKey)
        }
    }

    private func buildAnthropicRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String) throws -> URLRequest {
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

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 512,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userContent]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Build an OpenAI-compatible `/chat/completions` request. Shared by `.openai`
    /// (api.openai.com) and `.nebius` (api.studio.nebius.ai) — identical request
    /// body + SSE shape, only the base URL differs.
    private func buildOpenAICompatibleRequest(prompt: String, imageData: Data?, systemPrompt: String, apiKey: String, baseURL: String, model: String, toolsJSON: String? = nil) throws -> URLRequest {
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
            "max_tokens": 512,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
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
}
