import Foundation
@preconcurrency import LLM

/// Manages local AI model download and inference.
@MainActor
@Observable
final class LocalAIService {
    static let shared = LocalAIService()

    enum ModelState: Equatable {
        case loading
        case ready
        case error(String)
    }

    private(set) var state: ModelState = .loading
    nonisolated(unsafe) private var bot: LLM?

    // Model config — bundled with the app
    private let modelFileName = "qwen2.5-0.5b-instruct-q4_k_m"
    private let systemPrompt = """
    You are Drift AI, a brief health assistant. Rules:
    1. Answer in 1-3 short sentences. Never ramble.
    2. Use the context data provided. Don't invent numbers.
    3. When user wants to log food, respond: [LOG_FOOD: food name amount]
    4. When user wants to start a workout, respond: [START_WORKOUT: type]
    5. Be encouraging but honest about progress.
    6. For nutrition advice, reference their actual intake vs goals.
    Examples:
    User: "How am I doing?" → "You've eaten 1200 of your ~1800 target today. You're on track — maybe add a protein-rich dinner."
    User: "Log chicken" → "Sure! [LOG_FOOD: chicken breast 150g]"
    User: "Start leg day" → "Let's go! [START_WORKOUT: legs]"
    """

    private var modelPath: URL? {
        Bundle.main.url(forResource: modelFileName, withExtension: "gguf")
    }

    var isModelAvailable: Bool {
        modelPath != nil
    }

    init() {
        state = isModelAvailable ? .ready : .error("Model not found in app bundle")
    }

    // MARK: - Load Model

    func loadModel() {
        guard let path = modelPath, bot == nil else { return }
        state = .loading
        bot = LLM(from: path, template: .chatML(systemPrompt), historyLimit: 6, maxTokenCount: 512)
        if bot != nil {
            bot?.temp = 0.7
            bot?.topP = 0.9
            state = .ready
            Log.app.info("AI model loaded from bundle")
        } else {
            state = .error("Failed to load model")
        }
    }

    // MARK: - Inference

    /// Generate a response with health context injected.
    func respond(to message: String, context: String = "") async -> String {
        guard let bot else { return "Model not loaded." }

        let prompt: String
        if context.isEmpty {
            prompt = message
        } else {
            prompt = "Context about the user:\n\(context)\n\nUser: \(message)"
        }

        let localBot = bot
        await localBot.respond(to: prompt)
        return localBot.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the bot's live output (for streaming UI updates).
    var output: String {
        bot?.output ?? ""
    }

    func stop() {
        bot?.stop()
    }

    func reset() {
        bot?.reset()
    }

    func resetChat() {
        bot?.reset()
    }
}
