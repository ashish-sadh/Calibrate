import Testing
import Foundation
@testable import DriftCore

/// Guards the launch-time database recovery policy (#958): only a genuinely
/// corrupt file may be deleted+recreated. Transient disk-full / IO / permission
/// errors must be classified as NON-corruption so the recovery path never wipes
/// recoverable user data (and never crash-loops the launch via fatalError).
struct AppDatabaseInitializationTests {

    // MARK: - Corruption is deletable

    @Test func malformedImageIsCorruption() {
        let err = TestDBError("database disk image is malformed")
        #expect(AppDatabase.isCorruptionError(err))
    }

    @Test func notADatabaseIsCorruption() {
        let err = TestDBError("file is not a database")
        #expect(AppDatabase.isCorruptionError(err))
    }

    @Test func encryptedFileIsCorruption() {
        let err = TestDBError("file is encrypted or is not a database")
        #expect(AppDatabase.isCorruptionError(err))
    }

    // MARK: - Transient errors are NOT deletable

    @Test func diskIOErrorIsNotCorruption() {
        let err = TestDBError("disk I/O error")
        #expect(!AppDatabase.isCorruptionError(err))
    }

    @Test func diskFullIsNotCorruption() {
        let err = TestDBError("database or disk is full")
        #expect(!AppDatabase.isCorruptionError(err))
    }

    @Test func permissionDeniedIsNotCorruption() {
        let err = TestDBError("unable to open database file: permission denied")
        #expect(!AppDatabase.isCorruptionError(err))
    }

    @Test func genericErrorIsNotCorruption() {
        let err = TestDBError("some unexpected failure")
        #expect(!AppDatabase.isCorruptionError(err))
    }
}

private struct TestDBError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
