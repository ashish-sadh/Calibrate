import Testing
@testable import DriftCore

/// Tier 0 — pure backup progress label and payload-size formatting.
struct BackupPhaseTests {

    @Test func fixedPhasesHaveUserFacingMessages() {
        #expect(BackupPhase.snapshotting.message == "Copying your data…")
        #expect(BackupPhase.savingSettings.message == "Saving your settings…")
        #expect(BackupPhase.movingToCloud.message == "Moving to iCloud…")
        #expect(BackupPhase.uploading.message == "Uploading to iCloud…")
    }

    @Test func compressingMessageFormatsPayloadSize() {
        #expect(BackupPhase.compressing(bytes: 1_000_000).message == "Compressing backup (1 MB)…")
    }

    @Test func negativePayloadSizeIsClampedToZero() {
        #expect(BackupPhase.sizeString(-1) == BackupPhase.sizeString(0))
        #expect(BackupPhase.compressing(bytes: -1).message == "Compressing backup (Zero KB)…")
    }
}
