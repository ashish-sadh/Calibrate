import Foundation

/// Provider-agnostic interface for cloud vision. The UI and service layers
/// talk to this protocol so we can swap Anthropic / OpenAI implementations
/// without touching callers. #224 / #264.
protocol CloudVisionClient: Sendable {
    /// Send an image + text prompt to the provider and return a parsed
    /// `PhotoLogResponse`. Throws `CloudVisionError` on network / API /
    /// parsing failures. Hard 20s timeout per call.
    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse
}

/// Structured errors from cloud vision. Callers (PhotoLogService) map these
/// to user-facing copy in the review UI. #224.
enum CloudVisionError: Error, Equatable {
    case unauthorized                          // 401 — key revoked or bad
    case rateLimited                           // 429
    case timeout                               // > 20s or URLSession timeout
    case offline                               // no network reachable
    /// Non-2xx response where the provider included a structured error body.
    /// `message` is the human-readable reason pulled from `error.message` —
    /// surfaces things like "credit balance too low" or "invalid model id"
    /// that a generic "HTTP 400" would hide.
    case providerError(status: Int, message: String)
    case badResponse(Int)                      // non-2xx with no parsable body
    case malformedPayload                      // couldn't decode PhotoLogResponse from body
    case transport(String)                     // underlying URLSession error, redacted message
}

extension CloudVisionError: LocalizedError {
    /// Human-readable descriptions surfaced when a caller falls through to
    /// the generic `catch { error.localizedDescription }` path. Without this
    /// conformance users see "Drift.CloudVisionError error N" (#275).
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API key rejected (401). Check the key in Settings → Photo Log (Beta)."
        case .rateLimited:
            return "Provider is throttling (429). Try again in a minute."
        case .timeout:
            return "Provider didn't respond in time. Check your connection and try again."
        case .offline:
            return "No internet. Connect and try again."
        case .providerError(let status, let message):
            return "Provider rejected the request (HTTP \(status)): \(message)"
        case .badResponse(let code):
            return "Provider returned HTTP \(code). Try again in a moment."
        case .malformedPayload:
            return "Provider returned an unreadable response. Try a clearer photo."
        case .transport(let detail):
            return "Network error: \(detail)."
        }
    }
}

// MARK: - Anthropic implementation

/// Claude vision implementation. Uses the Messages API with a forced
/// `food_log` tool so we get structured JSON instead of free-text. The key
/// is read once per call from `CloudVisionKey`, never stored on the client.
struct AnthropicVisionClient: CloudVisionClient {
    static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let defaultModel = "claude-sonnet-4-6"
    static let apiVersion = "2023-06-01"
    static let timeoutSeconds: TimeInterval = 20

    let apiKey: String
    let endpoint: URL
    let model: String
    let session: URLSession

    init(
        apiKey: String,
        endpoint: URL = AnthropicVisionClient.defaultEndpoint,
        model: String = AnthropicVisionClient.defaultModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        let body = try Self.body(model: model, image: image, prompt: prompt)
        let data = try await send(body: body)
        return try Self.parseResponse(data)
    }

    /// Tiny text-only ping to validate the API key. Hits the Messages
    /// endpoint with a 1-token output cap so it's essentially free. Returns
    /// normally on any 2xx, throws the same `CloudVisionError` set on
    /// failure. Used by Settings [Test Connection]. #266.
    func ping() async throws {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        _ = try await send(body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Shared request/response wrapper for both `analyze` and `ping`. Sets
    /// the required Anthropic headers, applies the 20s timeout, and maps all
    /// network / HTTP failures into `CloudVisionError`.
    private func send(body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError {
            throw Self.mapURLError(err)
        } catch {
            throw CloudVisionError.transport("network failure")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CloudVisionError.badResponse(-1)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            // Keep the dedicated case — its error copy points users at the key field.
            throw CloudVisionError.unauthorized
        case 429:
            throw CloudVisionError.rateLimited
        default:
            // Non-2xx with a body Anthropic shaped as `{error:{type, message}}`.
            // Surface `message` verbatim so the user sees "credit balance too
            // low" / "invalid model id" instead of a generic "HTTP 400". The
            // earlier pass threw `.badResponse(400)` on low-credit accounts,
            // which made the real cause invisible — seen 2026-04-21.
            if let message = Self.extractErrorMessage(data) {
                throw CloudVisionError.providerError(status: http.statusCode, message: message)
            }
            throw CloudVisionError.badResponse(http.statusCode)
        }
    }

    /// Pull `error.message` out of an Anthropic error body. Returns nil when
    /// the body isn't the expected `{error:{message}}` shape so callers can
    /// fall back to the generic `.badResponse(code)` path.
    static func extractErrorMessage(_ data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        else { return nil }
        return message
    }

    // MARK: Request body

    /// Build the Messages API body with a base64 image block and a tool-use
    /// forcing structured JSON. Separate `static` so tests can snapshot it.
    static func body(model: String, image: Data, prompt: String) throws -> Data {
        let base64 = image.base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "tool_choice": ["type": "tool", "name": "food_log"],
            "tools": [[
                "name": "food_log",
                "description": "Return structured food identification and macros for the image.",
                "input_schema": Self.foodLogToolSchema
            ]],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    ["type": "text", "text": prompt]
                ] as [Any]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// JSON schema for the `food_log` tool Anthropic forces the model to
    /// fill. Computed each call to stay Sendable-clean without a lock.
    static var foodLogToolSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "grams": ["type": "number"],
                            "calories": ["type": "number"],
                            "protein_g": ["type": "number"],
                            "carbs_g": ["type": "number"],
                            "fat_g": ["type": "number"],
                            "confidence": ["type": "string", "enum": ["low", "medium", "high"]]
                        ],
                        "required": ["name", "confidence"]
                    ]
                ],
                "overall_confidence": ["type": "string", "enum": ["low", "medium", "high"]],
                "notes": ["type": "string"]
            ],
            "required": ["items", "overall_confidence"]
        ]
    }

    // MARK: Response parsing

    /// Extract the `food_log` tool-use input from a Messages response, then
    /// decode it as `PhotoLogResponse`. Surfaces `.malformedPayload` on
    /// any structural mismatch so callers don't have to guess.
    static func parseResponse(_ data: Data) throws -> PhotoLogResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentArray = root["content"] as? [[String: Any]]
        else {
            throw CloudVisionError.malformedPayload
        }
        let toolInput = contentArray.first { ($0["type"] as? String) == "tool_use" }?["input"]
        guard
            let input = toolInput,
            let inputData = try? JSONSerialization.data(withJSONObject: input),
            let parsed = try? JSONDecoder().decode(PhotoLogResponse.self, from: inputData)
        else {
            throw CloudVisionError.malformedPayload
        }
        return parsed
    }

    // MARK: Error mapping

    private static func mapURLError(_ err: URLError) -> CloudVisionError {
        switch err.code {
        case .timedOut: return .timeout
        case .notConnectedToInternet, .networkConnectionLost: return .offline
        default: return .transport("url \(err.code.rawValue)")
        }
    }
}

// MARK: - Shared transport helper

/// Same URLError → CloudVisionError mapping used by every provider. Extracted
/// so provider impls don't each re-declare it.
fileprivate func mapCloudVisionURLError(_ err: URLError) -> CloudVisionError {
    switch err.code {
    case .timedOut: return .timeout
    case .notConnectedToInternet, .networkConnectionLost: return .offline
    default: return .transport("url \(err.code.rawValue)")
    }
}

// MARK: - OpenAI implementation

/// OpenAI (`gpt-4o-mini`) implementation. Uses Chat Completions with
/// function calling forced to `food_log` so the model returns structured
/// JSON instead of prose. Same structured-error surfacing as the Anthropic
/// client — non-2xx bodies shaped as `{error:{message}}` bubble up as
/// `.providerError(status:message:)`.
struct OpenAIVisionClient: CloudVisionClient {
    static let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    /// gpt-4o-mini: vision-capable, ~$0.15/M input. Meal photos are tiny;
    /// per-call cost is sub-cent. Users can switch via `CloudVisionKey`
    /// when a dedicated provider override ships.
    static let defaultModel = "gpt-4o-mini"
    static let timeoutSeconds: TimeInterval = 20

    let apiKey: String
    let endpoint: URL
    let model: String
    let session: URLSession

    init(
        apiKey: String,
        endpoint: URL = OpenAIVisionClient.defaultEndpoint,
        model: String = OpenAIVisionClient.defaultModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        let body = try Self.body(model: model, image: image, prompt: prompt)
        let data = try await send(body: body)
        return try Self.parseResponse(data)
    }

    /// Tiny text-only ping. Used by Settings → Test Connection.
    func ping() async throws {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        _ = try await send(body: try JSONSerialization.data(withJSONObject: body))
    }

    private func send(body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError {
            throw Self.mapURLError(err)
        } catch {
            throw CloudVisionError.transport("network failure")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CloudVisionError.badResponse(-1)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw CloudVisionError.unauthorized
        case 429:
            throw CloudVisionError.rateLimited
        default:
            // OpenAI error shape matches Anthropic's on the `error.message`
            // field, so the same extractor works for both.
            if let message = AnthropicVisionClient.extractErrorMessage(data) {
                throw CloudVisionError.providerError(status: http.statusCode, message: message)
            }
            throw CloudVisionError.badResponse(http.statusCode)
        }
    }

    // MARK: Request body

    /// Build the Chat Completions body: data-URL image + forced function call.
    static func body(model: String, image: Data, prompt: String) throws -> Data {
        let dataURL = "data:image/jpeg;base64,\(image.base64EncodedString())"
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "tool_choice": ["type": "function", "function": ["name": "food_log"]],
            "tools": [[
                "type": "function",
                "function": [
                    "name": "food_log",
                    "description": "Return structured food identification and macros for the image.",
                    "parameters": AnthropicVisionClient.foodLogToolSchema
                ]
            ]],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": dataURL]],
                    ["type": "text", "text": prompt]
                ] as [Any]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: Response parsing

    /// OpenAI returns the function call under
    /// `choices[0].message.tool_calls[0].function.arguments` as a JSON
    /// STRING (not an object), so we parse twice: outer response → arguments
    /// string → PhotoLogResponse.
    static func parseResponse(_ data: Data) throws -> PhotoLogResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let toolCalls = message["tool_calls"] as? [[String: Any]],
            let function = toolCalls.first?["function"] as? [String: Any],
            let argumentsString = function["arguments"] as? String,
            let argsData = argumentsString.data(using: .utf8),
            let parsed = try? JSONDecoder().decode(PhotoLogResponse.self, from: argsData)
        else {
            throw CloudVisionError.malformedPayload
        }
        return parsed
    }

    private static func mapURLError(_ err: URLError) -> CloudVisionError {
        mapCloudVisionURLError(err)
    }
}

// MARK: - Google Gemini implementation

/// Google Gemini implementation (AI Studio / Generative Language API). Uses
/// function calling with `toolConfig.functionCallingConfig.mode = "ANY"` so
/// the model is forced to emit a `food_log` call. Key goes in the URL as
/// `?key=` per the Gemini API — no Authorization header.
struct GeminiVisionClient: CloudVisionClient {
    /// Default model. `gemini-2.5-flash` is the current vision-capable GA
    /// flash model on v1beta. `gemini-1.5-flash` was deprecated off the API;
    /// we saw a live 404 for it on 2026-04-21 before switching.
    static let defaultModel = "gemini-2.5-flash"
    static let defaultEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models"
    static let timeoutSeconds: TimeInterval = 20

    let apiKey: String
    let endpointBase: String
    let model: String
    let session: URLSession

    init(
        apiKey: String,
        endpointBase: String = GeminiVisionClient.defaultEndpointBase,
        model: String = GeminiVisionClient.defaultModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpointBase = endpointBase
        self.model = model
        self.session = session
    }

    /// Compose the `generateContent` URL with the key in the query string.
    /// The key never appears in headers or logs outside this getter.
    var endpoint: URL {
        URL(string: "\(endpointBase)/\(model):generateContent?key=\(apiKey)")!
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        let body = try Self.body(image: image, prompt: prompt)
        let data = try await send(body: body)
        return try Self.parseResponse(data)
    }

    /// Tiny text ping used by Settings → Test Connection. 8 tokens of
    /// headroom is enough to survive Gemini 2.5's hidden "thinking" budget
    /// before the response arrives — too low and we get HTTP 200 with an
    /// empty text part, which the user reads as "broken".
    func ping() async throws {
        let body: [String: Any] = [
            "contents": [["parts": [["text": "ping"]]]],
            "generationConfig": ["maxOutputTokens": 8]
        ]
        _ = try await send(body: try JSONSerialization.data(withJSONObject: body))
    }

    private func send(body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError {
            throw mapCloudVisionURLError(err)
        } catch {
            throw CloudVisionError.transport("network failure")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CloudVisionError.badResponse(-1)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            // Gemini uses 403 for invalid API key; treat as unauthorized so
            // UI copy points users at the key field.
            throw CloudVisionError.unauthorized
        case 429:
            throw CloudVisionError.rateLimited
        default:
            if let message = AnthropicVisionClient.extractErrorMessage(data) {
                throw CloudVisionError.providerError(status: http.statusCode, message: message)
            }
            throw CloudVisionError.badResponse(http.statusCode)
        }
    }

    // MARK: Request body

    /// Gemini `generateContent` body: inline image + forced function call.
    /// `toolConfig.functionCallingConfig.mode = "ANY"` with an explicit
    /// `allowedFunctionNames` is the Gemini equivalent of Anthropic's
    /// `tool_choice` — the model has to invoke `food_log`.
    static func body(image: Data, prompt: String) throws -> Data {
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": image.base64EncodedString()]],
                    ["text": prompt]
                ] as [Any]
            ]],
            "tools": [[
                "functionDeclarations": [[
                    "name": "food_log",
                    "description": "Return structured food identification and macros for the image.",
                    "parameters": AnthropicVisionClient.foodLogToolSchema
                ]]
            ]],
            "toolConfig": [
                "functionCallingConfig": [
                    "mode": "ANY",
                    "allowedFunctionNames": ["food_log"]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: Response parsing

    /// Gemini returns the function call under
    /// `candidates[0].content.parts[].functionCall.args` — `args` is already
    /// a parsed JSON object (unlike OpenAI's JSON-string `arguments`), so we
    /// serialize it back to bytes and decode as `PhotoLogResponse`.
    static func parseResponse(_ data: Data) throws -> PhotoLogResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw CloudVisionError.malformedPayload
        }
        let functionCall = parts.compactMap { $0["functionCall"] as? [String: Any] }.first
        guard
            let call = functionCall,
            let args = call["args"] as? [String: Any],
            let argsData = try? JSONSerialization.data(withJSONObject: args),
            let parsed = try? JSONDecoder().decode(PhotoLogResponse.self, from: argsData)
        else {
            throw CloudVisionError.malformedPayload
        }
        return parsed
    }
}
