import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — scan-over-scan body-composition breakdown + energy-balance
/// reconciliation. Pure logic; no DB, no device.
struct BodyCompositionAnalysisTests {

    private func scan(_ date: String, total: Double, fat: Double, lean: Double,
                      bone: Double? = nil, bf: Double? = nil) -> DEXAScan {
        DEXAScan(scanDate: date, totalMassKg: total, fatMassKg: fat, leanMassKg: lean,
                 boneMassKg: bone, bodyFatPct: bf)
    }

    // MARK: - Verdict classification

    @Test func recompositionDetected() {
        // Fat down 2kg, lean up 1kg.
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 20, lean: 57, bf: 25),
            current: scan("2026-04-01", total: 79, fat: 18, lean: 58, bf: 22)))
        #expect(d.verdict == .recomposition)
        #expect(d.narrative.contains("Recomposition"))
        #expect(d.days == 90)
    }

    @Test func fatLossWithLeanHeld() {
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 22, lean: 55),
            current: scan("2026-03-01", total: 77, fat: 19, lean: 55)))
        #expect(d.verdict == .fatLoss)
        // ~100% of the change was fat.
        #expect(d.fatFractionOfChange! > 0.95)
        #expect(d.narrative.contains("Fat loss"))
    }

    @Test func leanLossWarns() {
        // Lost weight but it was mostly muscle — the warning case.
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 20, lean: 57),
            current: scan("2026-03-01", total: 77, fat: 19.5, lean: 54.5)))
        #expect(d.verdict == .leanLoss)
        #expect(d.narrative.contains("protein"))
    }

    @Test func fatGainClassified() {
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 18, lean: 58),
            current: scan("2026-03-01", total: 83, fat: 21, lean: 58)))
        #expect(d.verdict == .fatGain)
    }

    @Test func noiseLevelChangeIsStable() {
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 20, lean: 57),
            current: scan("2026-03-01", total: 80.1, fat: 20.1, lean: 57.1)))
        #expect(d.verdict == .stable)
    }

    @Test func missingFieldsReturnNil() {
        let a = DEXAScan(scanDate: "2026-01-01", fatMassKg: 20)  // no lean
        let b = DEXAScan(scanDate: "2026-03-01", fatMassKg: 19, leanMassKg: 55)
        #expect(BodyCompositionAnalysis.scanDelta(previous: a, current: b) == nil)
    }

    // MARK: - Energy-balance reconciliation

    @Test func reconciliationAgreesWhenClose() {
        // 3 kg fat lost over 90 days = 3*7700/90 = -256.7 kcal/day.
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 22, lean: 55),
            current: scan("2026-04-01", total: 77, fat: 19, lean: 55)))
        let recon = try! #require(BodyCompositionAnalysis.reconcile(delta: d, estimatedDailyKcal: -300))
        #expect(recon.agrees)
        #expect(recon.dexaImpliedDailyKcal < 0)
        #expect(recon.narrative.contains("agree"))
    }

    @Test func reconciliationFlagsOppositeSign() {
        // Fat actually went UP while scale trend claims a deficit → mismatch.
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 18, lean: 58),
            current: scan("2026-03-01", total: 82, fat: 20, lean: 58)))
        let recon = try! #require(BodyCompositionAnalysis.reconcile(delta: d, estimatedDailyKcal: -400))
        #expect(!recon.agrees)
        #expect(recon.narrative.contains("Mismatch"))
    }

    @Test func reconciliationPartialWhenSameSignFarApart() {
        // 1 kg fat lost over 90d = -85 kcal/day, but estimate says -600 → same
        // sign, big gap.
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 20, lean: 57),
            current: scan("2026-04-01", total: 79, fat: 19, lean: 57)))
        let recon = try! #require(BodyCompositionAnalysis.reconcile(delta: d, estimatedDailyKcal: -600))
        #expect(!recon.agrees)
        #expect(recon.narrative.contains("Partial"))
    }

    @Test func reconciliationNeedsPositiveWindow() {
        let d = try! #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-03-01", total: 80, fat: 20, lean: 57),
            current: scan("2026-03-01", total: 79, fat: 19, lean: 57)))
        #expect(BodyCompositionAnalysis.reconcile(delta: d, estimatedDailyKcal: -300) == nil)
    }
}
