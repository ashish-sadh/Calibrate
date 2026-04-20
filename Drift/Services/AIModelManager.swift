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
    private let baseURL = "https://github.com/ashish-sadh/Drift/releases/download/models-v1"

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
        // Clean up incompatible model files from previous tier
        cleanupIncompatibleModels()
    }

    /// Remove model files that don't belong to the current tier (e.g., old Qwen3 vision files).
    private func cleanupIncompatibleModels() {
        let validNames = Set(currentTier.modelFiles.map(\.name))
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in contents where file.pathExtension == "gguf" {
            if !validNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
                Log.app.info("Removed incompatible model: \(file.lastPathComponent)")
            }
        }
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
        guard currentTier.modelFiles.count > 1, isModelDownloaded else { return nil }
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
            let url = URL(string: file.customURL ?? "\(baseURL)/\(file.name)")!
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

    private static let maxDownloadAttempts = 3
    private static let sizeToleranceFraction = 0.05  // allow ±5% size variance

    private func downloadFile(from url: URL, to destination: URL, fileSizeMB: Int, offsetMB: Int, totalMB: Int) async -> Bool {
        var lastError: Error?
        for attempt in 1...Self.maxDownloadAttempts {
            do {
                try await performDownload(from: url, to: destination, fileSizeMB: fileSizeMB, offsetMB: offsetMB, totalMB: totalMB)
                return true
            } catch let error as DownloadError {
                // Permanent errors (validation failures) — don't retry
                downloadState = .error(error.userMessage)
                Log.app.error("Download aborted (no retry): \(error.userMessage)")
                return false
            } catch {
                lastError = error
                let isRetryable = Self.isRetryable(error)
                Log.app.error("Download attempt \(attempt)/\(Self.maxDownloadAttempts) failed (retryable=\(isRetryable)): \(error.localizedDescription)")
                if !isRetryable || attempt == Self.maxDownloadAttempts { break }
                let backoffSeconds = UInt64(pow(2.0, Double(attempt - 1)))  // 1s, 2s, 4s
                try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
            }
        }
        let message = lastError.map { Self.friendlyMessage(for: $0) } ?? "Download failed. Please try again."
        downloadState = .error(message)
        return false
    }

    private func performDownload(from url: URL, to destination: URL, fileSizeMB: Int, offsetMB: Int, totalMB: Int) async throws {
        let tracker = ProgressTracker { [weak self] fileProgress in
            Task { @MainActor in
                let overall = (Double(offsetMB) + fileProgress * Double(fileSizeMB)) / Double(totalMB)
                self?.downloadState = .downloading(progress: min(overall, 0.99))
            }
        }
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 120  // per-packet idle timeout; large downloads can have gaps
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: tracker, delegateQueue: nil)
        let (tempURL, _) = try await session.download(from: url)

        // Size sanity check — reject truncated downloads before they reach the GGUF check
        // (a truncated file starting with GGUF magic would pass validation but fail to load).
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let actualBytes = (attrs[.size] as? Int64) ?? 0
        let expectedBytes = Int64(fileSizeMB) * 1024 * 1024
        let tolerance = Int64(Double(expectedBytes) * Self.sizeToleranceFraction)
        if expectedBytes > 0 && abs(actualBytes - expectedBytes) > tolerance {
            try? FileManager.default.removeItem(at: tempURL)
            let actualMB = Int(actualBytes / (1024 * 1024))
            throw DownloadError.sizeMismatch(expected: fileSizeMB, actual: actualMB)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        guard Self.isValidGGUF(at: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw DownloadError.invalidGGUF
        }
    }

    /// Check that a file starts with the GGUF magic bytes (0x47 0x47 0x55 0x46 = "GGUF").
    nonisolated static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { return false }
        return header == Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
    }

    enum DownloadError: Error {
        case sizeMismatch(expected: Int, actual: Int)
        case invalidGGUF

        var userMessage: String {
            switch self {
            case .sizeMismatch(let expected, let actual):
                return "Downloaded file size (\(actual) MB) does not match expected (\(expected) MB). Please try again."
            case .invalidGGUF:
                return "Downloaded file is not a valid model. Please try again."
            }
        }
    }

    nonisolated static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable,
             .internationalRoamingOff, .callIsActive, .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    nonisolated static func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
                return "No internet connection. Please connect to Wi-Fi and try again."
            case .timedOut, .networkConnectionLost:
                return "Download timed out. Please try again on a stronger connection."
            case .cancelled:
                return "Download cancelled."
            default:
                break
            }
        }
        return "Download failed: \(error.localizedDescription)"
    }

    // MARK: - Delete

    func deleteModel() {
        try? FileManager.default.removeItem(at: modelsDirectory)
        // Recreate empty directory for next download
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
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

// MARK: - Download Progress Tracker

private final class ProgressTracker: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async session.download(from:)
    }
}


