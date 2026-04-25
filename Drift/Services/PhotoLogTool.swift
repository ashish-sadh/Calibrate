import Foundation
import DriftCore
import UIKit

/// Tool-agent adapter for the Photo Log cloud vision pipeline. Registers a
/// schema with `ToolRegistry` only when the beta is on AND a provider key
/// exists, so non-beta users see no behaviour change and the LLM never
/// mentions a tool it can't actually use.
///
/// The LLM cannot pass image bytes through `ToolCallParams` (values are
/// `[String: String]`), so invocation happens via `run(image:prompt:)` from
/// the chat VM when the user attaches a photo. The registered handler
/// exists only so the tool shows up in prompts and logs — it surfaces a
/// help string if somehow called without an image. #224 / #268.
@MainActor
enum PhotoLogTool {
    nonisolated static let toolName = "photo_log"
    nonisolated static let defaultPrompt = "Identify each food item in this meal photo. Return grams, calories, and macros per item."

    /// True when the user has flipped on the beta toggle AND stored an API
    /// key for the currently-selected provider. `CloudVisionKey.has` is a
    /// metadata-only Keychain query — no biometrics prompt.
    static var isAvailable: Bool {
        Preferences.photoLogEnabled
            && CloudVisionKey.has(provider: Preferences.photoLogProvider)
    }

    /// Conditionally add the tool schema to `ToolRegistry`. Called from
    /// `ToolRegistration.registerAll`; also safe to call from tests.
    /// If the gate flips closed (user disabled the feature or cleared the
    /// key), the schema is removed so subsequent prompts don't list a
    /// tool that would refuse every call.
    static func syncRegistration(registry: ToolRegistry = .shared) {
        if isAvailable {
            registry.register(schema)
        } else {
            registry.unregister(name: toolName)
        }
    }

    /// Tool schema surfaced to the LLM. `prompt` is free-form user intent
    /// ("what are the macros?"). `image` isn't a param — the chat VM calls
    /// `run(image:prompt:)` directly once it has bytes.
    static var schema: ToolSchema {
        ToolSchema(
            id: "photolog.photo_log",
            name: toolName,
            service: "food",
            description: "User attached a meal photo — identify foods and macros via cloud vision.",
            parameters: [
                ToolParam("prompt", "string", "User note about the photo, if any", required: false)
            ],
            handler: { _ in
                // Reached only when the LLM tries to invoke photo_log without
                // an attached image. Surface a helpful message instead of an
                // error — the real path is the direct `run` call.
                .text("Attach a photo of your meal to use Photo Log.")
            }
        )
    }

    /// Direct invocation from the chat VM. Fetches the Keychain key once
    /// (biometric-gated), builds a client for the stored provider, runs the
    /// image through `PhotoLogService`, and returns a shaped `AgentOutput`.
    /// `service` is injectable for tests.
    static func run(
        image: UIImage,
        prompt: String = defaultPrompt,
        service: PhotoLogService? = nil
    ) async -> AgentOutput {
        guard isAvailable else {
            return AgentOutput(
                text: "Photo Log is off. Turn it on in Settings → Photo Log (Beta).",
                action: nil,
                toolsCalled: [toolName]
            )
        }
        do {
            let svc: PhotoLogService
            if let service {
                svc = service
            } else {
                svc = try await buildDefaultService()
            }
            let response = try await svc.analyze(image: image, prompt: prompt)
            return AgentOutput(
                text: summarize(response: response),
                action: nil,
                toolsCalled: [toolName]
            )
        } catch CloudVisionError.unauthorized {
            return errorOutput("Your API key was rejected. Re-add it in Settings → Photo Log (Beta).")
        } catch CloudVisionError.rateLimited {
            return errorOutput("Provider is throttling. Try again in a minute.")
        } catch CloudVisionError.timeout {
            return errorOutput("Photo analysis timed out. Check your connection and try again.")
        } catch CloudVisionError.offline, PhotoLogService.Error.offline {
            return errorOutput("Couldn't reach the provider. Check your connection and try again.")
        } catch let CloudVisionError.providerError(status, message) {
            // Surface the real reason (credit balance, invalid key, etc.) so
            // users know whether to add credit or re-enter the key.
            return errorOutput("Provider rejected the request (HTTP \(status)): \(message)")
        } catch CloudVisionError.malformedPayload {
            return errorOutput("Provider returned an unreadable response. Try a clearer photo.")
        } catch PhotoLogService.Error.encodingFailed {
            return errorOutput("Couldn't prepare that image. Try a different photo.")
        } catch CloudVisionKey.StorageError.notFound {
            return errorOutput("No key saved. Add one in Settings → Photo Log (Beta).")
        } catch {
            return errorOutput("Photo analysis failed. Try again in a moment.")
        }
    }

    // MARK: - Default service wiring

    private static func buildDefaultService() async throws -> PhotoLogService {
        let provider = Preferences.photoLogProvider
        guard let key = try await CloudVisionKey.get(for: provider) else {
            throw CloudVisionKey.StorageError.notFound
        }
        let model = Preferences.photoLogModel(for: provider)
        let client: CloudVisionClient
        switch provider {
        case .anthropic: client = AnthropicVisionClient(apiKey: key, model: model)
        case .openai:    client = OpenAIVisionClient(apiKey: key, model: model)
        case .gemini:    client = GeminiVisionClient(apiKey: key, model: model)
        }
        return PhotoLogService(client: client)
    }

    // MARK: - Summary formatting

    /// One-line chat summary. A richer per-item card can follow once the
    /// chat-attachment UI lands — the tool itself stays UI-agnostic.
    nonisolated static func summarize(response: PhotoLogResponse) -> String {
        guard !response.items.isEmpty else {
            return "Couldn't identify any food in that photo. Try one with the meal centered and in good light."
        }
        let visible = response.items.prefix(3).map(\.name).joined(separator: ", ")
        let more = response.items.count > 3 ? " +\(response.items.count - 3) more" : ""
        let totalCal = Int(response.items.reduce(0.0) { $0 + $1.calories }.rounded())
        let totalP = Int(response.items.reduce(0.0) { $0 + $1.proteinG }.rounded())
        let conf: String = switch response.overallConfidence {
        case .high: "high confidence"
        case .medium: "medium confidence"
        case .low: "low confidence"
        }
        return "Saw \(visible)\(more) — about \(totalCal) cal, \(totalP)g protein (\(conf)). Review before logging."
    }

    private static func errorOutput(_ text: String) -> AgentOutput {
        AgentOutput(text: text, action: nil, toolsCalled: [toolName])
    }
}
