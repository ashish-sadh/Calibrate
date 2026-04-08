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
    var isLargeModel: Bool { modelManager.currentTier == .large }

    private var systemPrompt: String {
        let screen = AIScreenTracker.shared.currentScreen.rawValue
        let tools = ToolRegistry.shared.schemaPrompt(forScreen: screen, isLargeModel: false)

        if isLargeModel {
            // Gemma 4: lightweight fallback prompt. Main path uses AIToolAgent + ToolRanker.
            return """
            You are a health tracking assistant. Answer questions about food, weight, and workouts. \
            Use data from context. Never give health advice. Never invent numbers.
            """
        } else {
            // Small model: concise prompt, filtered tools
            return """
            You help track food, weight, and workouts. \
            LOGGING (user ate/did something) → call log tool. \
            QUESTION (user asks about data) → call info tool. \
            CHAT (greeting, thanks) → respond naturally, no tool. \
            Never give health advice. Never invent numbers. \
            Examples: \
            "I had 2 eggs" → {"tool":"log_food","params":{"name":"eggs","amount":"2"}} \
            "calories left" → {"tool":"food_info","params":{}} \
            "how's my weight" → {"tool":"weight_info","params":{}} \
            "start chest workout" → {"tool":"start_workout","params":{"name":"chest"}} \
            "what should I train" → {"tool":"exercise_info","params":{}} \
            "how'd I sleep" → {"tool":"sleep_recovery","params":{}} \
            "thanks" → You're welcome! (no tool) \
            \(tools)
            """
        }
    }

    init() {
        ToolRegistration.registerAll()
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

        // Load on background thread so UI can show "Preparing AI assistant..." spinner
        let llama = LlamaCppBackend(modelPath: modelPath)
        Task.detached(priority: .userInitiated) {
            do {
                try llama.loadSync()
                await MainActor.run {
                    self.backend = llama
                    Task { await self.healthCheck() }
                }
            } catch {
                await MainActor.run {
                    Log.app.error("AI: load failed: \(error)")
                    self.state = .error(error.localizedDescription)
                }
            }
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

    // MARK: - Direct Backend Access (for agent pipeline)

    /// Respond with a custom system prompt, bypassing the built-in systemPrompt.
    /// Used by AIToolAgent so planner/chain/presentation steps don't get double-wrapped with tools.
    func respondDirect(systemPrompt: String, message: String) async -> String {
        guard let backend else { return "Model not loaded." }
        return await backend.respond(to: message, systemPrompt: systemPrompt)
    }

    func respondStreamingDirect(systemPrompt: String, message: String, onToken: @escaping @Sendable (String) -> Void) async -> String {
        guard let backend else { return "Model not loaded." }
        return await backend.respondStreaming(to: message, systemPrompt: systemPrompt, onToken: onToken)
    }

    // MARK: - Management

    private var unloadTimer: Timer?

    func stop() {
        // No-op for now
    }

    /// Unload model from GPU after a delay. Frees ~3GB GPU memory.
    /// Called when user leaves AI chat.
    func scheduleUnload(delay: TimeInterval = 60) {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.backend != nil else { return }
                Log.app.info("AI: unloading model (idle \(Int(delay))s)")
                self.backend?.unload()
                self.backend = nil
                // Keep state as .ready so it reloads on next use
                if self.modelManager.isModelDownloaded {
                    self.state = .ready
                }
            }
        }
    }

    /// Cancel pending unload — user came back to AI chat.
    func cancelUnload() {
        if unloadTimer != nil {
            Log.app.info("AI: unload cancelled (user returned)")
        }
        unloadTimer?.invalidate()
        unloadTimer = nil
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
