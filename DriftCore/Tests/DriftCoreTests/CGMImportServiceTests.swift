import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic CSV parsing with an isolated in-memory database.
struct CGMImportServiceTests {

    @Test func lingoFormatImportsValidRowsAndCountsRejectedRows() throws {
        let database = try AppDatabase.empty()
        let csv = """
        Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)
        2026-02-04T20:33-08:00,101
        2026-02-04T20:34-08:00,40
        2026-02-04T20:35-08:00,400
        2026-02-04T20:36-08:00,39
        2026-02-04T20:37-08:00,401
        2026-02-04T20:38-08:00,not-a-number
        malformed-row
        """

        let result = try importCSV(csv, into: database)

        #expect(result.imported == 3)
        #expect(result.skipped == 2)
        #expect(result.errors == 2)

        let readings = try database.fetchGlucoseReadings(from: "0000", to: "9999")
        #expect(readings.map(\.glucoseMgdl) == [101, 40, 400])
        #expect(readings.first?.timestamp == "2026-02-05T04:33:00Z")
        #expect(readings.allSatisfy { $0.source == "lingo_csv" })
        #expect(readings.allSatisfy { $0.importBatch == result.batchId })
    }

    @Test func genericFormatAcceptsSupportedDatesAndRejectsInvalidFields() throws {
        let database = try AppDatabase.empty()
        let csv = """
        timestamp,glucose_mg_dl
        2026-02-04 20:33:00,95
        02/05/2026 08:15:00,105
        invalid-date,110
        2026-02-05 09:00:00,invalid-glucose
        2026-02-05 09:05:00,35
        """

        let result = try importCSV(csv, into: database)

        #expect(result.imported == 2)
        #expect(result.skipped == 1)
        #expect(result.errors == 2)

        let readings = try database.fetchGlucoseReadings(from: "0000", to: "9999")
        #expect(readings.map(\.glucoseMgdl).sorted() == [95, 105])
        #expect(readings.allSatisfy { !$0.timestamp.isEmpty })
        #expect(readings.allSatisfy { $0.importBatch == result.batchId })
    }

    @Test func emptyFileReturnsZeroCountsWithoutPersistingReadings() throws {
        let database = try AppDatabase.empty()

        let result = try importCSV("\n  \n", into: database)

        #expect(result.imported == 0)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)
        #expect(!result.batchId.isEmpty)
        #expect(try database.fetchGlucoseReadings(from: "0000", to: "9999").isEmpty)
    }

    private func importCSV(_ content: String, into database: AppDatabase) throws -> CGMImportService.ImportResult {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CGMImportServiceTests-\(UUID().uuidString).csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try CGMImportService.importLingoCSV(url: url, database: database)
    }
}
