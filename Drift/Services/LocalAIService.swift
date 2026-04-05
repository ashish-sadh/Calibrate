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
    You are Drift AI, a concise health assistant inside a fitness tracking app. \
    You have the user's real health data in the context. Use actual numbers. \
    Be brief (2-4 sentences). Be encouraging but honest. \
    When user wants to log food: respond with [LOG_FOOD: food_name amount]. \
    When user wants to start workout: respond with [START_WORKOUT: type]. \
    When asked about unknown food nutrition: estimate with NUTRITION|name|cal|protein|carbs|fat|fiber|grams. \
    Never make up health data — only reference what's in the context.
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
        guard backend == nil else { return }
        state = .loading

        guard modelManager.isModelDownloaded, let modelPath = modelManager.primaryModelPath else {
            state = .notSetUp
            return
        }

        // llama.cpp backend
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
