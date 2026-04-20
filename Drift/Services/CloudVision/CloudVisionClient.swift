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
    case unauthorized        // 401 — key revoked or bad
    case rateLimited         // 429
    case timeout             // > 20s or URLSession timeout
    case offline             // no network reachable
    case badResponse(Int)    // any other non-2xx
    case malformedPayload    // couldn't decode PhotoLogResponse from body
    case transport(String)   // underlying URLSession error, redacted message
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Self.body(model: model, image: image, prompt: prompt)

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
            return try Self.parseResponse(data)
        case 401:
            throw CloudVisionError.unauthorized
        case 429:
            throw CloudVisionError.rateLimited
        default:
            throw CloudVisionError.badResponse(http.statusCode)
        }
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
