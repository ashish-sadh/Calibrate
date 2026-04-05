import Foundation
@preconcurrency import LLM

/// llama.cpp backend using LLM.swift — works on iOS 17+, any device.
final class LlamaCppBackend: AIBackend, @unchecked Sendable {
    nonisolated(unsafe) private var bot: LLM?
    private let modelPath: URL

    var isLoaded: Bool { bot != nil }
    var supportsVision: Bool { false }

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func loadSync() throws {
        try _load()
    }

    func load() async throws {
        try _load()
    }

    private func _load() throws {
        guard bot == nil else { return }
        let systemPrompt = """
        You are Drift AI, a brief health assistant. Rules:
        1. Answer in 1-3 short sentences. Never ramble.
        2. Use the context data provided. Don't invent numbers.
        3. When user wants to log food, respond: [LOG_FOOD: food name amount]
        4. When user wants to start a workout, respond: [START_WORKOUT: type]
        5. Be encouraging but honest about progress.
        Examples:
        User: "How am I doing?" → "You've eaten 1200 cal today. On track for your deficit goal."
        User: "Log chicken" → "Sure! [LOG_FOOD: chicken breast 150g]"
        """
        bot = LLM(from: modelPath, template: .chatML(systemPrompt), historyLimit: 6, maxTokenCount: 512)
        bot?.temp = 0.7
        bot?.topP = 0.9
    }

    func respond(to prompt: String, systemPrompt: String) async -> String {
        guard let bot else { return "Model not loaded." }
        await bot.respond(to: prompt)
        return bot.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        bot = nil
    }
}
