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
    Health & fitness assistant. Rules: \
    Use context data for health questions. Never invent numbers. \
    2-3 sentences. Be encouraging but honest. \
    When user wants an action, respond with the matching tag: \
    [LOG_FOOD: name amount] — log food \
    [LOG_WEIGHT: value unit] — log weight \
    [START_WORKOUT: template_name] — start existing template \
    [CREATE_WORKOUT: Exercise1 3x10@135, Exercise2 3x15] — build workout \
    If the user's intent is unclear, ask a clarifying question. \
    For data questions, start with the key insight.
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
            loadModel() // Auto-load after download
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
            Log.app.error("AI: model not downloaded or path missing")
            state = .notSetUp
            return
        }

        // Verify file isn't truncated/corrupted
        let expectedMB = modelManager.currentTier.modelFiles[0].sizeMB
        let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath.path)
        let actualMB = ((attrs?[.size] as? Int64) ?? 0) / (1024 * 1024)
        if actualMB < Int64(expectedMB) / 2 {
            Log.app.error("AI: model file too small (\(actualMB)MB, expected ~\(expectedMB)MB) — likely corrupted")
            modelManager.deleteModel()
            state = .error("Model file was corrupted. Please re-download.")
            return
        }

        // Pre-flight diagnostics
        let pathStr = modelPath.path
        let exists = FileManager.default.fileExists(atPath: pathStr)
        let readable = FileManager.default.isReadableFile(atPath: pathStr)
        let header = (try? Data(contentsOf: modelPath, options: .mappedIfSafe).prefix(4)) ?? Data()
        let isGGUF = header == Data([0x47, 0x47, 0x55, 0x46])
        Log.app.info("AI: path=\(modelPath.lastPathComponent) size=\(actualMB)MB exists=\(exists) readable=\(readable) gguf=\(isGGUF)")
        Log.app.info("AI: full path=\(pathStr)")

        guard exists, readable, isGGUF else {
            state = .error("Model file issue: exists=\(exists) readable=\(readable) gguf=\(isGGUF)")
            return
        }

        let llama = LlamaCppBackend(modelPath: modelPath)
        do {
            try llama.loadSync()
            backend = llama
            // Don't say ready yet — run a health check
            Task { await healthCheck() }
        } catch {
            Log.app.error("AI: load failed: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    /// Send a trivial prompt to verify the model actually works before declaring ready.
    private func healthCheck() async {
        guard let backend else {
            state = .error("Model not loaded.")
            return
        }
        Log.app.info("AI: running health check…")
        let result = await backend.respond(to: "Hi", systemPrompt: "Reply OK.")
        if result.isEmpty {
            Log.app.error("AI: health check returned empty — model broken")
            self.backend?.unload()
            self.backend = nil
            modelManager.deleteModel()
            state = .error("Model failed health check. Please re-download.")
        } else {
            Log.app.info("AI: health check passed (\(result.prefix(30)))")
            state = .ready
        }
    }

    // MARK: - Inference

    func respond(to message: String, context: String = "", history: String = "") async -> String {
        await respondStreaming(to: message, context: context, history: history, onToken: { _ in })
    }

    func respondStreaming(to message: String, context: String = "", history: String = "", onToken: @escaping @Sendable (String) -> Void) async -> String {
        guard let backend else { return "Model not loaded." }

        var parts: [String] = []
        if !context.isEmpty { parts.append("Context about the user:\n\(context)") }
        if !history.isEmpty { parts.append("Recent conversation:\n\(history)") }
        parts.append("User: \(message)")

        let prompt = parts.joined(separator: "\n\n")
        let b = backend
        return await b.respondStreaming(to: prompt, systemPrompt: systemPrompt, onToken: onToken)
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
