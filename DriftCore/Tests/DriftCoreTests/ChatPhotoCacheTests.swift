import XCTest
@testable import DriftCore

/// Tier-0 tests for ChatPhotoCache — pure filesystem scratch store backing the
/// Android chat photo attachment (#1174). No DB, no network.
/// Run: cd DriftCore && swift test --filter ChatPhotoCacheTests
final class ChatPhotoCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ChatPhotoCache.clear()
    }

    override func tearDown() {
        ChatPhotoCache.clear()
        super.tearDown()
    }

    private var jpeg: Data { Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03]) }

    func testStoreWritesFileAndRoundTripsBytes() throws {
        let url = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), jpeg)
        XCTAssertEqual(url.pathExtension, "jpg")
    }

    /// A re-attach must never collide with the previous file — Coil keys its
    /// image cache by URL, so a reused name would paint the OLD photo.
    func testTwoStoresProduceDistinctURLs() throws {
        let first = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        let second = try XCTUnwrap(ChatPhotoCache.store(Data([0xFF, 0xD8, 0x09])))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), jpeg)
        XCTAssertEqual(try Data(contentsOf: second), Data([0xFF, 0xD8, 0x09]))
    }

    func testRemoveDeletesOnlyThatFile() throws {
        let kept = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        let dropped = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        ChatPhotoCache.remove(dropped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dropped.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testClearEmptiesTheDirectory() throws {
        let a = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        let b = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        ChatPhotoCache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
    }

    func testClearOnAbsentDirectoryIsANoOp() {
        ChatPhotoCache.clear()
        ChatPhotoCache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChatPhotoCache.directory.path))
    }

    /// The GC: a store prunes yesterday's attachments and keeps today's. This
    /// replaced a wipe in `AIChatViewModel.init`, which Compose re-evaluated
    /// after an attach and which deleted the live thumbnail's file (#1174).
    func testStorePrunesStaleFilesAndKeepsFreshOnes() throws {
        let stale = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        let fresh = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ChatPhotoCache.maxAge - 60)],
            ofItemAtPath: stale.path)

        let newest = try XCTUnwrap(ChatPhotoCache.store(jpeg))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.path))
    }

    /// The photo just attached must survive the prune its own store triggers.
    func testStoreNeverPrunesTheFileItIsWriting() throws {
        let url = try XCTUnwrap(ChatPhotoCache.store(jpeg, now: Date().addingTimeInterval(60 * 60 * 24 * 30)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), jpeg)
    }

    /// Removing a URL that was already removed is the double-tap case on the
    /// input bar's X — it must stay silent.
    func testRemoveOfMissingFileIsSilent() throws {
        let url = try XCTUnwrap(ChatPhotoCache.store(jpeg))
        ChatPhotoCache.remove(url)
        ChatPhotoCache.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
