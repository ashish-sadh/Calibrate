import Foundation
import DriftCore

/// Orchestrates AI inference — picks backend (MLX or llama.cpp) and model tier based on device.
@MainActor
@Observable
public final class LocalAIService {
    public static let shared = LocalAIService()

    public enum State: Equatable {
        case notSetUp       // Model not downloaded
        case downloading(progress: Double)
        case loading        // Loading into memory
        case ready
        case error(String)
        case notEnoughSpace(String)
    }

    public private(set) var state: State = .notSetUp
    nonisolated(unsafe) private var backend: AIBackend?
    public let modelManager = AIModelManager.shared

    public var supportsVision: Bool { backend?.supportsVision ?? false }
    public var isModelLoaded: Bool { backend?.isLoaded ?? false }

    /// Tag what kind of backend is currently installed. The chat layer reads
    /// this to (a) pick the right system prompt via
    /// `IntentClassifier.activeSystemPrompt(backend:)` and (b) decide whether
    /// to display the cpu/cloud toggle. Defaults to `.foundationModels`
    /// (2026-05-19 LLM-swap migration) — callers should also gate on
    /// `state == .ready`.
    public private(set) var activeBackendType: AIBackendType = .foundationModels

    /// True when the active backend can fit the intelligencePrompt's richer
    /// extras. Local: only Gemma 4 / large tier. Remote: always (cloud LLMs
    /// are >10× the parameter count of Gemma 4). Used by the agent pipeline
    /// to gate clarification / multi-step reasoning that small models can't
    /// reliably do.
    public var isLargeModel: Bool {
        if activeBackendType == .remote { return true }
        return modelManager.currentTier == .large
    }

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
        // Tool registration is the iOS app's responsibility — DriftApp.init()
        // calls `ToolRegistration.registerAll()` after wiring DriftPlatform.
        if modelManager.isModelDownloaded {
            state = .ready
        } else if !DeviceCapability.hasEnoughDiskSpace(for: modelManager.currentTier) {
            state = .notEnoughSpace("Not enough storage for AI (\(modelManager.currentTier.downloadSizeMB)MB needed, keep 2GB free)")
        }
    }

    // MARK: - Setup

    public func downloadModel() async {
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

    public func loadModel() {
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

    public func respond(to message: String, context: String = "", history: String = "") async -> String {
        await respondStreaming(to: message, context: context, history: history, onToken: { _ in })
    }

    public func respondStreaming(to message: String, context: String = "", history: String = "", onToken: @escaping @Sendable (String) -> Void) async -> String {
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
    public func respondDirect(systemPrompt: String, message: String) async -> String {
        guard let backend else { return "Model not loaded." }
        return await backend.respond(to: message, systemPrompt: systemPrompt)
    }

    public func respondStreamingDirect(systemPrompt: String, message: String, onToken: @escaping @Sendable (String) -> Void) async -> String {
        guard let backend else { return "Model not loaded." }
        return await backend.respondStreaming(to: message, systemPrompt: systemPrompt, onToken: onToken)
    }

    /// Photo-capable variant for chat vision turns. Only works when the active
    /// backend is `RemoteLLMBackend` — local models have no vision capability.
    /// Returns "" (triggering the remote-error path in the VM) when no remote
    /// backend is installed.
    public func respondDirectWithPhoto(
        systemPrompt: String,
        message: String,
        imageData: Data,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        guard let remote = backend as? RemoteLLMBackend else { return "" }
        return await remote.respondStreamingWithPhoto(
            to: message, imageData: imageData,
            systemPrompt: systemPrompt, onToken: onToken
        )
    }

    // MARK: - Management

    private var unloadTimer: Timer?

    func stop() {
        // No-op for now
    }

    /// Unload model from GPU after a delay. Frees ~3GB GPU memory.
    /// Called when user leaves AI chat.
    public func scheduleUnload(delay: TimeInterval = 60) {
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
    public func cancelUnload() {
        if unloadTimer != nil {
            Log.app.info("AI: unload cancelled (user returned)")
        }
        unloadTimer?.invalidate()
        unloadTimer = nil
    }

    public func resetChat() {
        backend?.unload()
        backend = nil
        if modelManager.isModelDownloaded {
            loadModel()
        }
    }

    public func deleteModel() {
        backend?.unload()
        backend = nil
        modelManager.deleteModel()
        state = .notSetUp
    }

    // MARK: - Remote Backend (BYOK cloud)

    /// Install a remote BYOK backend (Anthropic / OpenAI / Gemini). The iOS
    /// app supplies the API key after a Keychain unlock — DriftCore never
    /// touches Keychain. Synchronous: cloud "load" is a no-op so we go
    /// straight to `.ready`. Mid-thread switch is safe: existing chat history
    /// lives in `AIChatViewModel.messages`, not in the backend. #515.
    public func useRemoteBackend(
        provider: RemoteLLMBackend.Provider,
        modelID: String,
        apiKey: String
    ) {
        backend?.unload()
        backend = RemoteLLMBackend(provider: provider, modelID: modelID, apiKey: apiKey)
        activeBackendType = .remote
        state = .ready
    }

    /// Drop any remote backend and revert to local-model behaviour. Caller is
    /// responsible for kicking off `loadModel()` if the local model is
    /// already downloaded. Used when the user flips the toggle back to "On
    /// device" mid-thread, or when the remote backend's key is cleared.
    public func clearRemoteBackend() {
        guard activeBackendType == .remote else { return }
        backend?.unload()
        backend = nil
        activeBackendType = .llamaCpp
        state = modelManager.isModelDownloaded ? .ready : .notSetUp
    }

    // MARK: - Foundation Models Backend (Apple Intelligence on-device)

    /// Install the Apple Foundation Models backend. Caller must verify
    /// availability first (`FoundationModelsBackend.isAvailableNow`) — this
    /// method assumes the runtime check has already passed. Mid-thread
    /// switch is safe: history lives in `AIChatViewModel.messages`, not in
    /// the backend instance.
    public func useFoundationModelsBackend() {
        backend?.unload()
        backend = FoundationModelsBackend()
        activeBackendType = .foundationModels
        // FM has no separate load step — system manages weights.
        state = .ready
    }

    /// Drop the FM backend. Used when the user flips away from FM in
    /// Settings, or when availability changes. Caller is responsible for
    /// installing the replacement (local model load or remote install).
    public func clearFoundationModelsBackend() {
        guard activeBackendType == .foundationModels else { return }
        backend?.unload()
        backend = nil
        activeBackendType = .llamaCpp
        state = modelManager.isModelDownloaded ? .ready : .notSetUp
    }

    /// True when the user has an installed local model OR a configured remote
    /// backend. Drives the empty-state chooser CTA — when this returns false,
    /// the chat shows the cloud-vs-on-device chooser instead of the input bar.
    /// Note: a local model that's downloaded but not yet loaded still counts
    /// as ready — we'll lazy-load on first use. #515.
    public var hasAnyBackendAvailable: Bool {
        if activeBackendType == .remote && backend != nil { return true }
        return modelManager.isModelDownloaded
    }

    /// Last error from a remote call, surfaced for the chat layer's Q7
    /// fallback decisions. nil for local backends or success cases.
    public var lastRemoteError: RemoteBackendError? {
        (backend as? RemoteLLMBackend)?.lastError
    }

    /// Display name of the active remote provider ("Anthropic", "OpenAI", "Gemini"),
    /// or nil when the local backend is in use. Stamped on assistant messages
    /// so the UI can show a per-turn cloud badge.
    public var remoteProviderName: String? {
        guard activeBackendType == .remote,
              let remote = backend as? RemoteLLMBackend else { return nil }
        return remote.provider.rawValue.capitalized
    }

    /// Device info for display.
    public var deviceInfo: String {
        let ram = String(format: "%.0f", DeviceCapability.ramGB)
        let free = String(format: "%.1f", DeviceCapability.freeDiskGB)
        let tier = modelManager.currentTier.displayName
        return "\(ram)GB RAM · \(free)GB free · \(tier)"
    }

    /// Download size for display.
    public var downloadSizeText: String {
        let mb = modelManager.currentTier.downloadSizeMB
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}
