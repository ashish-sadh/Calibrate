import Foundation
@testable import DriftCore
import Testing
import UIKit
import ImageIO
import DriftCore
@testable import Drift

// MARK: - Fakes

private actor FakeVisionClient: CloudVisionClient {
    private var callCount = 0
    private var lastPayload: Data? = nil
    let response: PhotoLogResponse
    let error: CloudVisionError?

    init(response: PhotoLogResponse = .stub, error: CloudVisionError? = nil) {
        self.response = response
        self.error = error
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        callCount += 1
        lastPayload = image
        if let error { throw error }
        return response
    }

    var calls: Int { callCount }
    var lastBytes: Data? { lastPayload }
}

private struct FakeReachability: ReachabilityChecking {
    let isOnline: Bool
}

extension PhotoLogResponse {
    static let stub = PhotoLogResponse(
        items: [PhotoLogItem(
            name: "apple", grams: 150, calories: 80,
            proteinG: 0, carbsG: 20, fatG: 0, confidence: .high
        )],
        overallConfidence: .high,
        notes: nil
    )
}

private func solidImage(size: CGSize, color: UIColor = .systemRed) -> UIImage {
    // scale = 1 so pixel size == logical size regardless of simulator DPI.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - Reachability gate

@Test func analyzeOfflineThrowsOfflineError() async throws {
    let client = FakeVisionClient()
    let svc = PhotoLogService(client: client, reachability: FakeReachability(isOnline: false))
    let img = solidImage(size: CGSize(width: 10, height: 10))
    await #expect(throws: PhotoLogService.Error.offline) {
        try await svc.analyze(image: img, prompt: "hi")
    }
    #expect(await client.calls == 0)
}

// MARK: - Preprocessing

@Test func preprocessDownscalesLargeImage() throws {
    let img = solidImage(size: CGSize(width: 4000, height: 3000))
    let bytes = try PhotoLogService.preprocess(img)
    // Sanity: output should be under the 1MB upload cap
    #expect(bytes.count < 1_000_000)
    // The encoded JPEG dims should reflect the downscale (long edge 1024)
    if let src = CGImageSourceCreateWithData(bytes as CFData, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let w = props[kCGImagePropertyPixelWidth] as? Int,
       let h = props[kCGImagePropertyPixelHeight] as? Int {
        #expect(max(w, h) <= 1024)
    } else {
        Issue.record("Could not read preprocessed JPEG dims")
    }
}

@Test func preprocessSkipsDownscaleForSmallImage() throws {
    let img = solidImage(size: CGSize(width: 300, height: 200))
    let bytes = try PhotoLogService.preprocess(img)
    if let src = CGImageSourceCreateWithData(bytes as CFData, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let w = props[kCGImagePropertyPixelWidth] as? Int {
        #expect(w == 300)
    }
}

@Test func preprocessStripsMetadata() throws {
    let img = solidImage(size: CGSize(width: 800, height: 600))
    let bytes = try PhotoLogService.preprocess(img)
    guard
        let src = CGImageSourceCreateWithData(bytes as CFData, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Could not read JPEG props")
        return
    }
    // GPS + EXIF user-personal dictionaries should not exist on our output.
    #expect(props[kCGImagePropertyGPSDictionary] == nil)
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        // A few fields can come from the encoder defaults (e.g. ColorSpace).
        // The ones we explicitly don't want — user-identifying fields — are
        // absent.
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifUserComment] == nil)
    }
}

// MARK: - Hashing

@Test func hashIsDeterministic() {
    let a = PhotoLogService.hash(Data([0x01, 0x02, 0x03]))
    let b = PhotoLogService.hash(Data([0x01, 0x02, 0x03]))
    #expect(a == b)
}

@Test func hashDiffersForDifferentBytes() {
    let a = PhotoLogService.hash(Data([0x01, 0x02, 0x03]))
    let b = PhotoLogService.hash(Data([0x01, 0x02, 0x04]))
    #expect(a != b)
}

// MARK: - Dedup cache

@Test func sameImageIsOnlyAnalyzedOnce() async throws {
    let client = FakeVisionClient()
    let svc = PhotoLogService(client: client, reachability: FakeReachability(isOnline: true))
    let img = solidImage(size: CGSize(width: 500, height: 500))

    let first = try await svc.analyze(image: img, prompt: "what")
    let second = try await svc.analyze(image: img, prompt: "what")

    #expect(first == second)
    #expect(await client.calls == 1)
}

@Test func differentImagesHitNetworkEachTime() async throws {
    let client = FakeVisionClient()
    let svc = PhotoLogService(client: client, reachability: FakeReachability(isOnline: true))
    let a = solidImage(size: CGSize(width: 500, height: 500), color: .red)
    let b = solidImage(size: CGSize(width: 500, height: 500), color: .blue)

    _ = try await svc.analyze(image: a, prompt: "x")
    _ = try await svc.analyze(image: b, prompt: "x")
    #expect(await client.calls == 2)
}

// MARK: - Error propagation

@Test func underlyingUnauthorizedPropagates() async throws {
    let client = FakeVisionClient(error: .unauthorized)
    let svc = PhotoLogService(client: client, reachability: FakeReachability(isOnline: true))
    let img = solidImage(size: CGSize(width: 100, height: 100))
    await #expect(throws: CloudVisionError.unauthorized) {
        try await svc.analyze(image: img, prompt: "x")
    }
}

// MARK: - Payload cap

@Test func uploadedPayloadStaysUnderOneMB() async throws {
    let client = FakeVisionClient()
    let svc = PhotoLogService(client: client, reachability: FakeReachability(isOnline: true))
    // Deliberately huge source — forces the preprocess path to kick in.
    let img = solidImage(size: CGSize(width: 6000, height: 4000))
    _ = try await svc.analyze(image: img, prompt: "x")
    let bytes = await client.lastBytes
    #expect((bytes?.count ?? 0) < 1_000_000)
}
