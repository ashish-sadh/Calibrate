import Foundation
@testable import DriftCore
import Testing

// CSV parser tests only - Lingo import tests are in UIFlowTests

@Test func parseSimpleCSV() async throws {
    let r = CSVParser.parse(content: "timestamp,glucose_mg_dl\n2026-03-15 08:00:00,95\n2026-03-15 08:05:00,97")
    #expect(r.headers.count == 2 && r.rows.count == 2)
    #expect(r.rows[0]["timestamp"] == "2026-03-15 08:00:00")
}

@Test func parseEmptyCSV() async throws { #expect(CSVParser.parse(content: "").rows.isEmpty) }
@Test func parseHeaderOnly() async throws { #expect(CSVParser.parse(content: "a,b,c").rows.isEmpty) }

@Test func parseQuotedFields() async throws {
    let r = CSVParser.parse(content: "name,value\n\"hello, world\",42\nsimple,10")
    #expect(r.rows.count == 2 && r.rows[0]["name"] == "hello, world")
}
