import Testing
@testable import DriftCore

@Suite struct LabTextParserDateBoundaryTests {

    @Test func ambiguousNumericDateUsesConfiguredFieldOrder() {
        let lines = ["Collected: 03/04/2026"]

        #expect(LabTextParser.detectReportDate(from: lines) == "2026-03-04")
        #expect(LabTextParser.detectReportDate(from: lines, dayFirst: true) == "2026-04-03")
    }

    @Test func unambiguousNumericDateOverridesConfiguredFieldOrder() {
        #expect(LabTextParser.detectReportDate(
            from: ["Collected: 14/02/2026"]
        ) == "2026-02-14")
        #expect(LabTextParser.detectReportDate(
            from: ["Collected: 02/14/2026"],
            dayFirst: true
        ) == "2026-02-14")
    }

    @Test func collectionDateTakesPriorityOverReceivedAndReportedDates() {
        let lines = [
            "Received On: 03/05/2026",
            "Reported: 03/06/2026",
            "Collected: 03/04/2026",
        ]

        #expect(LabTextParser.detectReportDate(from: lines) == "2026-03-04")
    }

    @Test func writtenAndISODateShapesAreSupported() {
        #expect(LabTextParser.detectReportDate(
            from: ["Collected March 7, 2026"]
        ) == "2026-03-07")
        #expect(LabTextParser.detectReportDate(
            from: ["Collected 7 Mar 2026"]
        ) == "2026-03-07")
        #expect(LabTextParser.detectReportDate(
            from: ["Collected 2026-03-07"]
        ) == "2026-03-07")
    }

    @Test func detectedIndianLabMakesAmbiguousReportDateDayFirst() {
        let output = LabTextParser.parse(text: """
        Dr Lal PathLabs
        Collected: 03/04/2026
        """)

        #expect(output.labName == "Dr Lal PathLabs")
        #expect(output.reportDate == "2026-04-03")
    }
}
