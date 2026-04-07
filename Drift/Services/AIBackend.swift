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
enum AIModelTier: Sendable {
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
        case .large: 2900
        }
    }

    var modelFiles: [ModelFile] {
        switch self {
        case .small:
            return [ModelFile(name: "smollm2-360m-instruct-q8_0.gguf", sizeMB: 368)]
        case .large:
            return [ModelFile(name: "gemma-4-e2b-q4_k_m.gguf", sizeMB: 2900,
                              customURL: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")]
        }
    }

    struct ModelFile: Sendable {
        let name: String
        let sizeMB: Int
        var customURL: String? = nil  // Override download URL (for HuggingFace, etc.)
    }
}

// MARK: - Backend Type

enum AIBackendType: Sendable {
    case llamaCpp
    case mlx
}

// MARK: - Device Capability Detection

enum DeviceCapability {
    /// Whether this device can run AI at all (6GB+ RAM).
    static var canRunAI: Bool {
        ramGB >= 5.5
    }

    /// Detect the best model tier + backend for this device.
    static func detectTier() -> (tier: AIModelTier, backend: AIBackendType) {
        // physicalMemory reports total RAM but iOS reserves 1-2GB
        // iPhone 16 Pro (8GB) reports ~7.2-7.8, iPhone 15 (6GB) reports ~5.2-5.8
        if ramGB >= 6.5 {
            return (.large, .llamaCpp)  // Gemma 4 (2.9GB) — 8GB devices (Pro models)
        } else if ramGB >= 5.0 {
            return (.small, .llamaCpp)  // SmolLM2 (368MB) — 6GB devices
        } else {
            return (.small, .llamaCpp)  // SmolLM2 — older devices
        }
    }

    /// Check if there's enough free disk space for the model.
    /// Ensures at least 2GB remains free after download.
    static func hasEnoughDiskSpace(for tier: AIModelTier) -> Bool {
        let needed = Int64(tier.downloadSizeMB) * 1024 * 1024 + 2 * 1024 * 1024 * 1024 // model + 2GB buffer
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? docsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return false }
        return available > needed
    }

    /// Free disk space in GB.
    static var freeDiskGB: Double {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? docsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Double(available) / (1024 * 1024 * 1024)
    }

    /// Device RAM in GB.
    static var ramGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
