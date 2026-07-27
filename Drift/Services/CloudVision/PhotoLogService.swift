import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import DriftCore
import Network

/// Orchestrates the photo-to-food pipeline: preprocess the image, hash it,
/// hit the configured cloud vision provider, and cache recent results so a
/// debug re-run doesn't re-bill the user. #224 / #265.
///
/// Image handling rules (see design):
/// - Downscale long edge to 1024 px before upload.
/// - Re-encode as JPEG at 0.7 quality (no metadata) — strips GPS, device,
///   timestamp, orientation flags the server doesn't need.
/// - Never written to disk; the `UIImage` and `Data` are released as soon as
///   the network call returns.
/// - SHA-256 of the uploaded bytes is the dedup key, not the raw UIImage —
///   so bytes on the wire are what's compared.
final class PhotoLogService: @unchecked Sendable {
    static let maxLongEdge: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.7
    static let cacheLimit = 20
    /// Belt-and-braces cap on the uploaded payload; the 1024 px + 0.7 JPEG
    /// combo stays well under this in practice.
    static let maxUploadBytes = 1_000_000

    enum Error: Swift.Error, Equatable {
        case encodingFailed
        case offline
    }

    private let client: CloudVisionClient
    private let reachability: ReachabilityChecking
    private let cache = ResponseCache()

    init(client: CloudVisionClient, reachability: ReachabilityChecking = NetworkReachability.shared) {
        self.client = client
        self.reachability = reachability
    }

    /// Preprocess, check cache, maybe call the provider. Always returns a
    /// parsed `PhotoLogResponse` — errors bubble up as `CloudVisionError` or
    /// `PhotoLogService.Error`.
    func analyze(image: UIImage, prompt: String) async throws -> PhotoLogResponse {
        guard reachability.isOnline else { throw Error.offline }

        let uploadBytes = try Self.preprocess(image)
        let key = Self.hash(uploadBytes)
        if let hit = await cache.get(key) {
            return hit
        }
        let response = try await client.analyze(image: uploadBytes, prompt: prompt)
        await cache.put(key, value: response, limit: Self.cacheLimit)
        return response
    }

    // MARK: - Preprocessing

    /// Produce JPEG bytes ready for upload. Downscales so the long edge is
    /// at most `maxLongEdge`, re-encodes at `jpegQuality`, and writes with
    /// no metadata (ImageIO skips GPS / EXIF by default when we don't copy
    /// source metadata in).
    static func preprocess(_ image: UIImage) throws -> Data {
        let downscaled = downscale(image, longEdge: maxLongEdge)
        guard let cg = downscaled.cgImage else { throw Error.encodingFailed }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw Error.encodingFailed }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Error.encodingFailed }
        let data = mutable as Data
        if data.count > maxUploadBytes {
            // Re-try with a tighter quality — rare path for very large inputs.
            return try tightenJPEG(cg, targetBytes: maxUploadBytes)
        }
        return data
    }

    private static func downscale(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let size = image.size
        let maxEdge = max(size.width, size.height)
        guard maxEdge > longEdge else { return image }
        let scale = longEdge / maxEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func tightenJPEG(_ cg: CGImage, targetBytes: Int) throws -> Data {
        for q in stride(from: 0.6, through: 0.3, by: -0.1) {
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                mutable, UTType.jpeg.identifier as CFString, 1, nil
            ) else { continue }
            CGImageDestinationAddImage(dest, cg, [
                kCGImageDestinationLossyCompressionQuality: q
            ] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }
            if (mutable as Data).count <= targetBytes { return mutable as Data }
        }
        throw Error.encodingFailed
    }

    // MARK: - Hashing

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Response cache

/// Bounded FIFO cache. Actor so concurrent analyze() calls don't race the
/// eviction list.
private actor ResponseCache {
    private var entries: [(key: String, value: PhotoLogResponse)] = []

    func get(_ key: String) -> PhotoLogResponse? {
        entries.first { $0.key == key }?.value
    }

    func put(_ key: String, value: PhotoLogResponse, limit: Int) {
        entries.removeAll { $0.key == key }
        entries.append((key, value))
        while entries.count > limit { entries.removeFirst() }
    }
}

// MARK: - Reachability

/// Tiny protocol so tests can inject an offline state without monkey-patching
/// Network framework internals.
protocol ReachabilityChecking: Sendable {
    var isOnline: Bool { get }
}

final class NetworkReachability: ReachabilityChecking, @unchecked Sendable {
    static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "drift.reachability")
    private let lock = NSLock()
    private var latestStatus: NWPath.Status = .satisfied

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.latestStatus = path.status
        }
        monitor.start(queue: queue)
    }

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return latestStatus == .satisfied
    }
}
