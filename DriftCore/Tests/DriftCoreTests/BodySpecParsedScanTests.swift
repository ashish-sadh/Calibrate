import Testing
@testable import DriftCore

/// Tier 0 — pure value contracts for the cross-platform BodySpec parser output.
@Suite struct BodySpecParsedScanTests {

    @Test func initializerDefaultsOptionalMeasurementsAndRegions() {
        let scan = BodySpecParsedScan(scanDate: "2026-07-21")

        #expect(scan.scanDate == "2026-07-21")
        #expect(scan.bodyFatPct == nil)
        #expect(scan.totalMassLbs == nil)
        #expect(scan.fatMassLbs == nil)
        #expect(scan.leanMassLbs == nil)
        #expect(scan.bmcLbs == nil)
        #expect(scan.rmrCalories == nil)
        #expect(scan.vatMassLbs == nil)
        #expect(scan.vatVolumeIn3 == nil)
        #expect(scan.agRatio == nil)
        #expect(scan.boneDensityTotal == nil)
        #expect(scan.regions.isEmpty)
    }

    @Test func initializerPreservesMeasurementsAndRegions() throws {
        let scan = BodySpecParsedScan(
            scanDate: "2026-07-21",
            bodyFatPct: 18.4,
            totalMassLbs: 176.2,
            fatMassLbs: 32.4,
            leanMassLbs: 137.1,
            bmcLbs: 6.7,
            rmrCalories: 1_684,
            vatMassLbs: 0.72,
            vatVolumeIn3: 19.6,
            agRatio: 0.91,
            boneDensityTotal: 1.24,
            regions: [
                BodySpecParsedRegion(
                    name: "Android",
                    fatPct: 20.1,
                    totalMassLbs: 15.2,
                    fatMassLbs: 3.1,
                    leanMassLbs: 11.8,
                    bmcLbs: 0.3
                ),
            ]
        )

        #expect(scan.scanDate == "2026-07-21")
        #expect(scan.bodyFatPct == 18.4)
        #expect(scan.totalMassLbs == 176.2)
        #expect(scan.fatMassLbs == 32.4)
        #expect(scan.leanMassLbs == 137.1)
        #expect(scan.bmcLbs == 6.7)
        #expect(scan.rmrCalories == 1_684)
        #expect(scan.vatMassLbs == 0.72)
        #expect(scan.vatVolumeIn3 == 19.6)
        #expect(scan.agRatio == 0.91)
        #expect(scan.boneDensityTotal == 1.24)

        let region = try #require(scan.regions.first)
        #expect(region.name == "Android")
        #expect(region.fatPct == 20.1)
        #expect(region.totalMassLbs == 15.2)
        #expect(region.fatMassLbs == 3.1)
        #expect(region.leanMassLbs == 11.8)
        #expect(region.bmcLbs == 0.3)
    }
}
