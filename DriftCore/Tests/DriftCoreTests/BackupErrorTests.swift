@testable import DriftCore
import Testing

@Suite struct BackupErrorTests {
    @Test func iCloudAvailabilityErrorsHaveActionableMessages() {
        #expect(
            BackupError.iCloudUnavailable.userMessage
                == "iCloud Drive is off or you're signed out of iCloud. Backup needs iCloud Drive enabled in Settings."
        )
        #expect(
            BackupError.quotaExceeded.userMessage
                == "Your iCloud storage is full — free up space or upgrade to keep backups running."
        )
    }

    @Test func corruptedBackupMessageDoesNotExposeTechnicalDetail() {
        let error = BackupError.corrupted("checksum mismatch in database.sqlite")

        #expect(error.userMessage == "The backup file failed its integrity check. The next backup will replace it.")
    }

    @Test func invalidFormatMessageIncludesUsefulDetail() {
        let error = BackupError.invalidFormat("manifest.json is missing")

        #expect(error.userMessage == "The backup couldn't be written (manifest.json is missing).")
    }

    @Test func newerSchemaAndFormatVersionsShareUpdateGuidance() {
        let expected = "This backup was made by a newer version of Drift — update the app to restore it."

        #expect(BackupError.unsupportedSchemaVersion(backupVersion: 12, current: 11).userMessage == expected)
        #expect(BackupError.unsupportedFormatVersion(backupVersion: 3, current: 2).userMessage == expected)
    }

    @Test func uploadFailureMessageDoesNotExposeTechnicalDetail() {
        let error = BackupError.uploadFailed("connection reset by peer")

        #expect(
            error.userMessage
                == "Couldn't reach iCloud — check your connection. Drift will retry automatically."
        )
    }
}
