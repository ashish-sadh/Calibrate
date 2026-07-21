import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure backup manifest metadata and JSON coding contracts.
struct BackupManifestTests {

    @Test func initializerUsesCurrentFormatVersionAndPreservesFileMetadata() {
        let timestamp = Date(timeIntervalSince1970: 1_774_051_200)
        let file = BackupManifest.FileEntry(sha256: "abc123", sizeBytes: 4_096)

        let manifest = BackupManifest(
            appBuild: "842",
            appVersion: "2.7.1",
            timestamp: timestamp,
            schemaVersion: 19,
            files: ["drift.sqlite": file]
        )

        #expect(BackupManifest.currentFormatVersion == 1)
        #expect(manifest.backupFormatVersion == BackupManifest.currentFormatVersion)
        #expect(manifest.appBuild == "842")
        #expect(manifest.appVersion == "2.7.1")
        #expect(manifest.timestamp == timestamp)
        #expect(manifest.schemaVersion == 19)
        #expect(manifest.files["drift.sqlite"] == file)
    }

    @Test func encoderUsesISO8601DatesAndStablePrettyPrintedKeyOrder() throws {
        let timestamp = try #require(
            ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z")
        )
        let manifest = BackupManifest(
            appBuild: "842",
            appVersion: "2.7.1",
            timestamp: timestamp,
            schemaVersion: 19,
            files: ["drift.sqlite": .init(sha256: "abc123", sizeBytes: 4_096)]
        )

        let data = try BackupManifest.encoder().encode(manifest)
        let text = try #require(String(data: data, encoding: .utf8))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["timestamp"] as? String == "2026-03-20T12:00:00Z")
        #expect(text.contains("\n  \"appBuild\""))

        let orderedKeys = [
            "appBuild", "appVersion", "backupFormatVersion", "files",
            "schemaVersion", "timestamp",
        ]
        var previousIndex: String.Index?
        for key in orderedKeys {
            let index = try #require(text.range(of: "\"\(key)\"")?.lowerBound)
            if let previousIndex {
                #expect(previousIndex < index)
            }
            previousIndex = index
        }
    }

    @Test func decoderReadsStandaloneISO8601Manifest() throws {
        let data = Data(
            #"{"timestamp":"2026-03-20T12:00:00Z","schemaVersion":19,"files":{"preferences.json":{"sizeBytes":512,"sha256":"def456"}},"appVersion":"2.7.1","appBuild":"842","backupFormatVersion":3}"#.utf8
        )

        let manifest = try BackupManifest.decoder().decode(BackupManifest.self, from: data)

        #expect(manifest.backupFormatVersion == 3)
        #expect(manifest.appBuild == "842")
        #expect(manifest.appVersion == "2.7.1")
        #expect(manifest.timestamp == ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z"))
        #expect(manifest.schemaVersion == 19)
        #expect(
            manifest.files["preferences.json"]
                == BackupManifest.FileEntry(sha256: "def456", sizeBytes: 512)
        )
    }
}
