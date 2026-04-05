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

    /// Unload model from memory.
    func unload()
}

// MARK: - Model Tier

/// Which model to download based on device capabilities.
enum AIModelTier: Sendable {
    case small   // SmolLM2-360M Q8 (~368MB) — 6GB devices
    case large   // Qwen2.5-1.5B Q4_K_M (~1065MB) — 8GB+ devices, best quality

    var displayName: String {
        switch self {
        case .small: "SmolLM2"
        case .large: "Qwen 1.5B"
        }
    }

    var downloadSizeMB: Int {
        switch self {
        case .small: 368
        case .large: 1065
        }
    }

    var modelFiles: [ModelFile] {
        switch self {
        case .small:
            return [ModelFile(name: "smollm2-360m-instruct-q8_0.gguf", sizeMB: 368)]
        case .large:
            return [ModelFile(name: "qwen2.5-1.5b-instruct-q4_k_m.gguf", sizeMB: 1065)]
        }
    }

    struct ModelFile: Sendable {
        let name: String
        let sizeMB: Int
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
        if ramGB >= 7.5 {
            return (.large, .llamaCpp)
        } else {
            return (.small, .llamaCpp)
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
