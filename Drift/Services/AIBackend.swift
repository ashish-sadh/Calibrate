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
    case small   // Qwen2.5-0.5B text-only (~491MB) — 6GB devices
    case large   // Qwen2.5-1.5B text (~1.12GB) — 8GB+ devices, much smarter

    var displayName: String {
        switch self {
        case .small: "Standard"
        case .large: "Advanced"
        }
    }

    var downloadSizeMB: Int {
        switch self {
        case .small: 491
        case .large: 1120
        }
    }

    var modelFiles: [ModelFile] {
        switch self {
        case .small:
            return [ModelFile(name: "qwen2.5-0.5b-instruct-q4_k_m.gguf", sizeMB: 491)]
        case .large:
            return [ModelFile(name: "qwen2.5-1.5b-instruct-q4_k_m.gguf", sizeMB: 1120)]
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
            // 8GB+ device — 1.5B model via llama.cpp
            return (.large, .llamaCpp)
        } else {
            // 6GB device — 0.5B model
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
