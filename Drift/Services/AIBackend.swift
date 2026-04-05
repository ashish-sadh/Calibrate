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
    case small   // Qwen2.5-0.5B text-only (~491MB) — any device
    case vision  // Qwen3-VL-2B vision+text (~1.55GB) — 8GB+ devices

    var displayName: String {
        switch self {
        case .small: "Standard"
        case .vision: "Advanced (with vision)"
        }
    }

    var downloadSizeMB: Int {
        switch self {
        case .small: 491
        case .vision: 1550
        }
    }

    var modelFiles: [ModelFile] {
        switch self {
        case .small:
            return [ModelFile(name: "qwen2.5-0.5b-instruct-q4_k_m.gguf", sizeMB: 491)]
        case .vision:
            return [
                ModelFile(name: "Qwen3-VL-2B-Instruct-Q4_K_M.gguf", sizeMB: 1110),
                ModelFile(name: "mmproj-Qwen3-VL-2B-Q8_0.gguf", sizeMB: 445),
            ]
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
    /// Detect the best model tier + backend for this device.
    static func detectTier() -> (tier: AIModelTier, backend: AIBackendType) {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion

        // iOS 18+ required for MLX
        let canUseMLX = osVersion.majorVersion >= 18

        if ramGB >= 7.5 && canUseMLX {
            // 8GB device (iPhone 15 Pro+) — vision model via MLX
            return (.vision, .mlx)
        } else if canUseMLX {
            // 6GB device with iOS 18+ — small model via MLX (faster than llama.cpp)
            return (.small, .mlx)
        } else {
            // Older iOS or small device — llama.cpp fallback
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
