import Testing
@testable import DriftCore

/// Tier 0 — CSV shape and whitespace behavior used by generic CGM imports.
struct CSVParserEdgeCaseTests {

    @Test func whitespaceOnlyLinesAreSkippedAndCellsAreTrimmed() {
        let result = CSVParser.parse(content: " name , value \n\n   \n alpha , 42 ")

        #expect(result.rows.count == 1)
        #expect(result.rows[0]["name"] == "alpha")
        #expect(result.rows[0]["value"] == "42")
    }

    @Test func emptyCellsArePreserved() {
        let result = CSVParser.parse(content: "name,note,value\nalpha,,\n,second,3")

        #expect(result.rows[0]["note"] == "")
        #expect(result.rows[0]["value"] == "")
        #expect(result.rows[1]["name"] == "")
    }

    @Test func unevenRowsMapOnlyValuesWithMatchingHeaders() {
        let result = CSVParser.parse(content: "a,b\n1\n2,3,ignored")

        #expect(result.rows[0] == ["a": "1"])
        #expect(result.rows[1] == ["a": "2", "b": "3"])
    }

    @Test func quotedHeaderCanContainAComma() {
        let result = CSVParser.parse(content: "\"recorded,at\",glucose\n\"2026-07-21 08:00\",101")

        #expect(result.headers == ["recorded,at", "glucose"])
        #expect(result.rows[0]["recorded,at"] == "2026-07-21 08:00")
        #expect(result.rows[0]["glucose"] == "101")
    }
}
