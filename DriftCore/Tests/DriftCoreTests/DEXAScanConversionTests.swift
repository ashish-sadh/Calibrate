import Testing
@testable import DriftCore

/// Tier 0 — deterministic unit conversions for DEXA scan measurements.
@Suite struct DEXAScanConversionTests {

    @Test func kilogramMeasurementsConvertToPounds() throws {
        let scan = DEXAScan(
            scanDate: "2026-07-21",
            totalMassKg: 80,
            fatMassKg: 16,
            leanMassKg: 60,
            boneMassKg: 4,
            visceralFatKg: 1.25
        )

        #expect(try #require(scan.totalMassLbs) == 80 * 2.20462)
        #expect(try #require(scan.fatMassLbs) == 16 * 2.20462)
        #expect(try #require(scan.leanMassLbs) == 60 * 2.20462)
        #expect(try #require(scan.bmcLbs) == 4 * 2.20462)
        #expect(try #require(scan.visceralFatLbs) == 1.25 * 2.20462)
    }

    @Test func absentKilogramMeasurementsRemainAbsent() {
        let scan = DEXAScan(scanDate: "2026-07-21", bodyFatPct: 20)

        #expect(scan.totalMassLbs == nil)
        #expect(scan.fatMassLbs == nil)
        #expect(scan.leanMassLbs == nil)
        #expect(scan.bmcLbs == nil)
        #expect(scan.visceralFatLbs == nil)
    }

    @Test func eachConversionDependsOnlyOnItsMatchingMeasurement() throws {
        let scan = DEXAScan(scanDate: "2026-07-21", leanMassKg: 50)

        #expect(try #require(scan.leanMassLbs) == 50 * 2.20462)
        #expect(scan.totalMassLbs == nil)
        #expect(scan.fatMassLbs == nil)
        #expect(scan.bmcLbs == nil)
        #expect(scan.visceralFatLbs == nil)
    }

    @Test func zeroKilogramsConvertsToZeroPounds() {
        let scan = DEXAScan(
            scanDate: "2026-07-21",
            totalMassKg: 0,
            fatMassKg: 0,
            leanMassKg: 0,
            boneMassKg: 0,
            visceralFatKg: 0
        )

        #expect(scan.totalMassLbs == 0)
        #expect(scan.fatMassLbs == 0)
        #expect(scan.leanMassLbs == 0)
        #expect(scan.bmcLbs == 0)
        #expect(scan.visceralFatLbs == 0)
    }
}
