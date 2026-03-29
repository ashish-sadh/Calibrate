import Foundation
import Testing
@testable import Drift

@Test func parseSimpleCSV() async throws {
    let csv = """
    timestamp,glucose_mg_dl
    2026-03-15 08:00:00,95
    2026-03-15 08:05:00,97
    2026-03-15 08:10:00,102
    """

    let result = CSVParser.parse(content: csv)
    #expect(result.headers.count == 2)
    #expect(result.rows.count == 3)
    #expect(result.rows[0]["timestamp"] == "2026-03-15 08:00:00")
    #expect(result.rows[0]["glucose_mg_dl"] == "95")
}

@Test func parseEmptyCSV() async throws {
    let result = CSVParser.parse(content: "")
    #expect(result.headers.isEmpty)
    #expect(result.rows.isEmpty)
}

@Test func parseHeaderOnly() async throws {
    let result = CSVParser.parse(content: "a,b,c")
    #expect(result.headers.count == 3)
    #expect(result.rows.isEmpty)
}

@Test func parseQuotedFields() async throws {
    let csv = """
    name,value
    "hello, world",42
    simple,10
    """

    let result = CSVParser.parse(content: csv)
    #expect(result.rows.count == 2)
    #expect(result.rows[0]["name"] == "hello, world")
}

@Test func lingoRealFormatImport() async throws {
    let csv = """
    Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)
    2026-02-04T20:33-08:00,101
    2026-02-04T18:43-08:00,99
    2026-02-04T18:38-08:00,103
    2026-02-04T18:33-08:00,107
    2026-02-04T17:18-08:00,87
    """

    // Write to temp file
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_lingo.csv")
    try csv.write(to: tempURL, atomically: true, encoding: .utf8)

    let db = try AppDatabase.empty()
    let result = try CGMImportService.importLingoCSV(url: tempURL, database: db)

    #expect(result.imported == 5)
    #expect(result.errors == 0)
    #expect(result.skipped == 0)

    // Verify readings were saved (timestamps converted to UTC, -08:00 offset = +8hrs)
    // 2026-02-04T17:18-08:00 = 2026-02-05T01:18:00Z
    // 2026-02-04T20:33-08:00 = 2026-02-05T04:33:00Z
    let readings = try db.fetchGlucoseReadings(from: "2026-02-04T00:00:00Z", to: "2026-02-06T00:00:00Z")
    #expect(readings.count == 5)

    try FileManager.default.removeItem(at: tempURL)
}

@Test func lingoTimestampNormalization() async throws {
    // Test the Lingo timestamp format: "2026-02-04T20:33-08:00"
    let csv = """
    Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)
    2026-02-04T20:33-08:00,101
    """

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_lingo2.csv")
    try csv.write(to: tempURL, atomically: true, encoding: .utf8)

    let db = try AppDatabase.empty()
    let result = try CGMImportService.importLingoCSV(url: tempURL, database: db)

    #expect(result.imported == 1)
    #expect(result.errors == 0)

    try FileManager.default.removeItem(at: tempURL)
}
