import Foundation

/// Manages AI model download, storage, and deletion.
@MainActor
@Observable
final class AIModelManager {
    static let shared = AIModelManager()

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case completed
        case error(String)
    }

    private(set) var downloadState: DownloadState = .idle
    private(set) var currentTier: AIModelTier
    private(set) var backendType: AIBackendType

    // Base URL for model downloads — GitHub Releases (primary), HuggingFace (fallback for vision)
    private var baseURL: String {
        switch currentTier {
        case .small:
            return "https://github.com/ashish-sadh/Drift/releases/download/models-v1"
        case .vision:
            return "https://huggingface.co/unsloth/Qwen3-VL-2B-Instruct-GGUF/resolve/main"
        }
    }

    private var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DriftAI")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        let detected = DeviceCapability.detectTier()
        self.currentTier = detected.tier
        self.backendType = detected.backend
    }

    // MARK: - Model Status

    var isModelDownloaded: Bool {
        currentTier.modelFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(file.name).path)
        }
    }

    func modelPath(for fileName: String) -> URL {
        modelsDirectory.appendingPathComponent(fileName)
    }

    var primaryModelPath: URL? {
        guard isModelDownloaded else { return nil }
        return modelPath(for: currentTier.modelFiles[0].name)
    }

    var visionProjectorPath: URL? {
        guard currentTier == .vision, currentTier.modelFiles.count > 1, isModelDownloaded else { return nil }
        return modelPath(for: currentTier.modelFiles[1].name)
    }

    // MARK: - Download

    func downloadModel() async {
        guard !isModelDownloaded else { downloadState = .completed; return }

        // Check disk space
        guard DeviceCapability.hasEnoughDiskSpace(for: currentTier) else {
            let needed = currentTier.downloadSizeMB
            downloadState = .error("Not enough storage. Need \(needed)MB + 2GB free. You have \(String(format: "%.1f", DeviceCapability.freeDiskGB))GB free.")
            return
        }

        downloadState = .downloading(progress: 0)

        let files = currentTier.modelFiles
        let totalSize = files.reduce(0) { $0 + $1.sizeMB }

        var downloadedMB = 0
        for file in files {
            let url = URL(string: "\(baseURL)/\(file.name)")!
            let dest = modelPath(for: file.name)

            // Skip if this file already exists
            if FileManager.default.fileExists(atPath: dest.path) {
                downloadedMB += file.sizeMB
                continue
            }

            let offsetMB = downloadedMB
            let success = await downloadFile(from: url, to: dest, fileSizeMB: file.sizeMB, offsetMB: offsetMB, totalMB: totalSize)
            if !success { return }
            downloadedMB += file.sizeMB
        }

        downloadState = .completed
        Log.app.info("AI model downloaded: \(self.currentTier.displayName)")
    }

    private func downloadFile(from url: URL, to destination: URL, fileSizeMB: Int, offsetMB: Int, totalMB: Int) async -> Bool {
        do {
            // Use default session (follows redirects automatically)
            // Track progress via bytes received
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
            let totalBytes = response.expectedContentLength
            var data = Data()
            data.reserveCapacity(fileSizeMB * 1024 * 1024)
            var received: Int64 = 0

            for try await byte in asyncBytes {
                data.append(byte)
                received += 1
                if received % (512 * 1024) == 0 { // Update every 512KB
                    let fileProgress = totalBytes > 0 ? Double(received) / Double(totalBytes) : 0
                    let overallProgress = (Double(offsetMB) + fileProgress * Double(fileSizeMB)) / Double(totalMB)
                    downloadState = .downloading(progress: min(overallProgress, 0.99))
                }
            }

            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination)
            return true
        } catch {
            downloadState = .error("Download failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delete

    func deleteModel() {
        try? FileManager.default.removeItem(at: modelsDirectory)
        downloadState = .idle
        Log.app.info("AI model deleted")
    }

    /// Size of downloaded model on disk in MB.
    var modelSizeOnDiskMB: Int {
        let files = currentTier.modelFiles
        var total: Int64 = 0
        for file in files {
            let path = modelPath(for: file.name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return Int(total / (1024 * 1024))
    }
}



