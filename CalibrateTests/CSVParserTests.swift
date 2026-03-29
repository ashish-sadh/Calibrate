import Testing
@testable import Calibrate

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
