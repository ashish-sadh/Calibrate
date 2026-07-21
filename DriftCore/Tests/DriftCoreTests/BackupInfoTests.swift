import Foundation
import Testing
@testable import DriftCore

struct BackupInfoTests {
    private let url = URL(fileURLWithPath: "/tmp/drift-2026-07-21.driftbackup")
    private let timestamp = Date(timeIntervalSince1970: 1_774_051_200)

    @Test func manifestInitializerProjectsAllMetadata() {
        let manifest = BackupManifest(
            backupFormatVersion: 3,
            appBuild: "842",
            appVersion: "2.7.1",
            timestamp: timestamp,
            schemaVersion: 19,
            files: ["drift.sqlite": .init(sha256: "abc123", sizeBytes: 4_096)]
        )

        let info = BackupInfo(url: url, manifest: manifest)

        #expect(info.url == url)
        #expect(info.timestamp == timestamp)
        #expect(info.appVersion == "2.7.1")
        #expect(info.appBuild == "842")
        #expect(info.backupFormatVersion == 3)
        #expect(info.schemaVersion == 19)
    }

    @Test func directInitializerPreservesMetadata() {
        let info = BackupInfo(
            url: url,
            timestamp: timestamp,
            appVersion: "2.7.1",
            appBuild: "842",
            backupFormatVersion: 3,
            schemaVersion: 19
        )

        #expect(info.url == url)
        #expect(info.timestamp == timestamp)
        #expect(info.appVersion == "2.7.1")
        #expect(info.appBuild == "842")
        #expect(info.backupFormatVersion == 3)
        #expect(info.schemaVersion == 19)
    }

    @Test func identityUsesURLWhileValueSemanticsIncludeMetadata() {
        let original = BackupInfo(
            url: url,
            timestamp: timestamp,
            appVersion: "2.7.1",
            appBuild: "842",
            backupFormatVersion: 3,
            schemaVersion: 19
        )
        let rescanned = BackupInfo(
            url: url,
            timestamp: timestamp.addingTimeInterval(60),
            appVersion: "2.7.2",
            appBuild: "843",
            backupFormatVersion: 3,
            schemaVersion: 20
        )

        #expect(original.id == rescanned.id)
        #expect(original != rescanned)
        #expect(Set([original, original]).count == 1)
        #expect(Set([original, rescanned]).count == 2)
    }
}
