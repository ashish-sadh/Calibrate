import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure value and persistence-coding contracts for regional DEXA data.
@Suite struct DEXARegionTests {
    @Test func initializerDefaultsOptionalMeasurementsToAbsent() {
        let region = DEXARegion(scanId: 42, region: "trunk")

        #expect(region.id == nil)
        #expect(region.scanId == 42)
        #expect(region.region == "trunk")
        #expect(region.fatPct == nil)
        #expect(region.totalMassLbs == nil)
        #expect(region.fatMassLbs == nil)
        #expect(region.leanMassLbs == nil)
        #expect(region.bmcLbs == nil)
    }

    @Test func initializerPreservesEveryRegionalMeasurement() {
        let region = DEXARegion(
            id: 9,
            scanId: 42,
            region: "l_arm",
            fatPct: 18.4,
            totalMassLbs: 9.8,
            fatMassLbs: 1.8,
            leanMassLbs: 7.6,
            bmcLbs: 0.4
        )

        #expect(region.id == 9)
        #expect(region.scanId == 42)
        #expect(region.region == "l_arm")
        #expect(region.fatPct == 18.4)
        #expect(region.totalMassLbs == 9.8)
        #expect(region.fatMassLbs == 1.8)
        #expect(region.leanMassLbs == 7.6)
        #expect(region.bmcLbs == 0.4)
    }

    @Test func codableUsesPersistenceFieldNamesAndRoundTrips() throws {
        let original = DEXARegion(
            id: 9,
            scanId: 42,
            region: "l_arm",
            fatPct: 18.4,
            totalMassLbs: 9.8,
            fatMassLbs: 1.8,
            leanMassLbs: 7.6,
            bmcLbs: 0.4
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["scan_id"] as? Int == 42)
        #expect(object["fat_pct"] as? Double == 18.4)
        #expect(object["total_mass_lbs"] as? Double == 9.8)
        #expect(object["fat_mass_lbs"] as? Double == 1.8)
        #expect(object["lean_mass_lbs"] as? Double == 7.6)
        #expect(object["bmc_lbs"] as? Double == 0.4)
        #expect(object["scanId"] == nil)
        #expect(object["fatPct"] == nil)

        let decoded = try JSONDecoder().decode(DEXARegion.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.scanId == original.scanId)
        #expect(decoded.region == original.region)
        #expect(decoded.fatPct == original.fatPct)
        #expect(decoded.totalMassLbs == original.totalMassLbs)
        #expect(decoded.fatMassLbs == original.fatMassLbs)
        #expect(decoded.leanMassLbs == original.leanMassLbs)
        #expect(decoded.bmcLbs == original.bmcLbs)
    }
}
