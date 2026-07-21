import Testing
@testable import DriftCore

@Suite struct LabReportDisplayDateTests {
    @Test func validReportDateUsesDayDisplayFormat() {
        let report = LabReport(
            reportDate: "2026-07-21",
            fileName: "lab-results.pdf"
        )

        #expect(report.displayDate == "Tue, Jul 21")
    }

    @Test func malformedReportDateFallsBackToStoredValue() {
        let report = LabReport(
            reportDate: "date unavailable",
            fileName: "lab-results.pdf"
        )

        #expect(report.displayDate == "date unavailable")
    }
}
