import Foundation
import Testing
@testable import Drift

@Test func gemma4DeclaredSizeMatchesHFFile() async throws {
    // HF file is ~2963 MB — if this drifts, download disk-space check becomes wrong.
    let large = AIModelTier.large
    #expect(large.downloadSizeMB == 2963)
    #expect(large.modelFiles[0].sizeMB == 2963)
}

@Test func gemma4URLIsPinnedToRevision() async throws {
    // Revision pinning protects against silent file-size/content drift.
    let url = AIModelTier.large.modelFiles[0].customURL
    #expect(url != nil)
    if let url {
        #expect(!url.contains("/resolve/main/"), "URL should pin a commit revision, not use /resolve/main/")
        #expect(url.contains("f064409f340b34190993560b2168133e5dbae558"), "URL should be pinned to expected revision")
    }
}

@Test func isValidGGUFRejectsEmptyFile() async throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).gguf")
    FileManager.default.createFile(atPath: tmp.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(AIModelManager.isValidGGUF(at: tmp) == false)
}

@Test func isValidGGUFRejectsNonGGUFFile() async throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).gguf")
    FileManager.default.createFile(atPath: tmp.path, contents: Data([0x00, 0x01, 0x02, 0x03, 0x04]))
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(AIModelManager.isValidGGUF(at: tmp) == false)
}

@Test func isValidGGUFAcceptsGGUFMagic() async throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("good-\(UUID().uuidString).gguf")
    FileManager.default.createFile(atPath: tmp.path, contents: Data([0x47, 0x47, 0x55, 0x46, 0x00, 0x00]))
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(AIModelManager.isValidGGUF(at: tmp) == true)
}

@Test func retryableURLErrorsIncludeTransientNetworkFailures() async throws {
    let cases: [URLError.Code] = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .dnsLookupFailed,
    ]
    for code in cases {
        #expect(AIModelManager.isRetryable(URLError(code)), "URLError.\(code) should be retryable")
    }
}

@Test func nonRetryableErrorsAreNotRetried() async throws {
    let cases: [URLError.Code] = [.badURL, .unsupportedURL, .cancelled]
    for code in cases {
        #expect(AIModelManager.isRetryable(URLError(code)) == false, "URLError.\(code) should NOT be retryable")
    }
    #expect(AIModelManager.isRetryable(NSError(domain: "x", code: 1)) == false)
}

@Test func friendlyMessageTranslatesOfflineError() async throws {
    let msg = AIModelManager.friendlyMessage(for: URLError(.notConnectedToInternet))
    #expect(msg.contains("internet") || msg.contains("Wi-Fi"))
}

@Test func friendlyMessageTranslatesTimeout() async throws {
    let msg = AIModelManager.friendlyMessage(for: URLError(.timedOut))
    #expect(msg.lowercased().contains("timed out"))
}
