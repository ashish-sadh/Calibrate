import Foundation

// MARK: - AI Backend Protocol

/// Abstraction for on-device LLM inference. Supports both llama.cpp and MLX backends.
protocol AIBackend: AnyObject, Sendable {
    var isLoaded: Bool { get }
    var supportsVision: Bool { get }

    /// Load the model into memory. Call after download.
    func load() async throws

    /// Generate a text response.
    func respond(to prompt: String, systemPrompt: String) async -> String

    /// Generate a text response with streaming — calls onToken for each piece of text.
    func respondStreaming(to prompt: String, systemPrompt: String, onToken: @escaping @Sendable (String) -> Void) async -> String

    /// Unload model from memory.
    func unload()
}

// MARK: - Model Tier

/// Which model to download based on device capabilities.
/// Public because `AIModelManager.currentTier: AIModelTier` is read by iOS
/// (e.g. `FloatingAIAssistant` compares `currentTier == .large`).
public enum AIModelTier: Sendable {
    case small   // SmolLM2-360M Q8 (~368MB) — 6GB devices
    case large   // Gemma 4 E2B Q4_K_M (~2900MB) — 8GB+ devices, best tool calling

    var displayName: String {
        switch self {
        case .small: "SmolLM2"
        case .large: "Gemma 4"
        }
    }

    var downloadSizeMB: Int {
        switch self {
        case .small: 368
        case .large: 2963
        }
    }

    var modelFiles: [ModelFile] {
        switch self {
        case .small:
            return [ModelFile(name: "smollm2-360m-instruct-q8_0.gguf", sizeMB: 368)]
        case .large:
            // Pinned revision prevents silent file-size drift when the unsloth repo updates.
            return [ModelFile(name: "gemma-4-e2b-q4_k_m.gguf", sizeMB: 2963,
                              customURL: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/f064409f340b34190993560b2168133e5dbae558/gemma-4-E2B-it-Q4_K_M.gguf")]
        }
    }

    struct ModelFile: Sendable {
        let name: String
        let sizeMB: Int
        var customURL: String? = nil  // Override download URL (for HuggingFace, etc.)
    }
}

// MARK: - Backend Type

/// Public because it appears as a property type on `AIModelManager.backendType`.
public enum AIBackendType: String, Sendable {
    case llamaCpp
    case mlx
    case remote
    /// Apple Foundation Models — on-device, system-managed weights, iOS 26+
    /// + Apple-Intelligence-eligible devices. `FoundationModelsBackend`
    /// returns false from `isLoaded` if the runtime check fails, so the
    /// chat layer routes around it the same way it routes around an
    /// undownloaded local model.
    case foundationModels
}

// MARK: - Device Capability Detection

public enum DeviceCapability {
    /// Whether this device can run AI at all (6GB+ RAM).
    public static var canRunAI: Bool {
        ramGB >= 5.5
    }

    /// Detect the best model tier + backend for this device.
    ///
    /// **2026-05-19 LLM-swap migration:** Drift now defaults to Apple
    /// Foundation Models (iOS 26+, Apple-Intelligence-eligible hardware).
    /// FoundationModelsBackend.isLoaded gates availability at runtime —
    /// if a device can't run FM, the chat layer routes around it the
    /// same way it routes around an undownloaded local model.
    ///
    /// Tier is still returned (.small / .large) for legacy callers that
    /// switch on it, but the backend is always .foundationModels going
    /// forward. The .llamaCpp case in `AIBackendType` is kept for
    /// transitional UI references; never returned by detectTier.
    public static func detectTier() -> (tier: AIModelTier, backend: AIBackendType) {
        if ramGB >= 6.5 {
            return (.large, .foundationModels)  // Apple FM on 8GB+ devices
        } else if ramGB >= 5.0 {
            return (.small, .foundationModels)
        } else {
            return (.small, .foundationModels)
        }
    }

    /// Check if there's enough free disk space for the model.
    /// Ensures at least 2GB remains free after download.
    public static func hasEnoughDiskSpace(for tier: AIModelTier) -> Bool {
        let needed = Int64(tier.downloadSizeMB) * 1024 * 1024 + 2 * 1024 * 1024 * 1024 // model + 2GB buffer
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? docsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return false }
        return available > needed
    }

    /// Free disk space in GB.
    public static var freeDiskGB: Double {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? docsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Double(available) / (1024 * 1024 * 1024)
    }

    /// Device RAM in GB.
    public static var ramGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
