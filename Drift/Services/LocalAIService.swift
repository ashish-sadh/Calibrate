import Foundation

/// Orchestrates AI inference — picks backend (MLX or llama.cpp) and model tier based on device.
@MainActor
@Observable
final class LocalAIService {
    static let shared = LocalAIService()

    enum State: Equatable {
        case notSetUp       // Model not downloaded
        case downloading(progress: Double)
        case loading        // Loading into memory
        case ready
        case error(String)
        case notEnoughSpace(String)
    }

    private(set) var state: State = .notSetUp
    nonisolated(unsafe) private var backend: AIBackend?
    let modelManager = AIModelManager.shared

    var supportsVision: Bool { backend?.supportsVision ?? false }
    var isModelLoaded: Bool { backend?.isLoaded ?? false }

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

    init() {
        if modelManager.isModelDownloaded {
            state = .ready
        } else if !DeviceCapability.hasEnoughDiskSpace(for: modelManager.currentTier) {
            state = .notEnoughSpace("Not enough storage for AI (\(modelManager.currentTier.downloadSizeMB)MB needed, keep 2GB free)")
        }
    }

    // MARK: - Setup

    func downloadModel() async {
        await modelManager.downloadModel()
        switch modelManager.downloadState {
        case .completed:
            state = .ready
        case .error(let msg):
            state = .error(msg)
        default:
            break
        }
    }

    func loadModel() {
        guard modelManager.isModelDownloaded, backend == nil else { return }
        state = .loading

        guard let modelPath = modelManager.primaryModelPath else {
            state = .error("Model file not found")
            return
        }

        // Create appropriate backend
        let llama = LlamaCppBackend(modelPath: modelPath)
        try? llama.loadSync()
        backend = llama
        state = llama.isLoaded ? .ready : .error("Failed to load model")
    }

    // MARK: - Inference

    func respond(to message: String, context: String = "") async -> String {
        guard let backend else { return "Model not loaded." }

        let prompt: String
        if context.isEmpty {
            prompt = message
        } else {
            prompt = "Context about the user:\n\(context)\n\nUser: \(message)"
        }

        let b = backend
        return await b.respond(to: prompt, systemPrompt: systemPrompt)
    }

    // MARK: - Management

    func stop() {
        // No-op for now — LLM.swift doesn't expose cancel cleanly
    }

    func resetChat() {
        backend?.unload()
        backend = nil
        if modelManager.isModelDownloaded {
            loadModel()
        }
    }

    func deleteModel() {
        backend?.unload()
        backend = nil
        modelManager.deleteModel()
        state = .notSetUp
    }

    /// Device info for display.
    var deviceInfo: String {
        let ram = String(format: "%.0f", DeviceCapability.ramGB)
        let free = String(format: "%.1f", DeviceCapability.freeDiskGB)
        let tier = modelManager.currentTier.displayName
        return "\(ram)GB RAM · \(free)GB free · \(tier)"
    }

    /// Download size for display.
    var downloadSizeText: String {
        let mb = modelManager.currentTier.downloadSizeMB
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}
