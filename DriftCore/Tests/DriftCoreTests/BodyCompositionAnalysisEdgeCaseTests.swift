import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic edge cases for scan comparison and reconciliation.
@Suite struct BodyCompositionAnalysisEdgeCaseTests {
    private func scan(
        _ date: String,
        total: Double? = nil,
        fat: Double,
        lean: Double,
        bone: Double? = nil,
        bodyFatPct: Double? = nil
    ) -> DEXAScan {
        DEXAScan(
            scanDate: date,
            totalMassKg: total,
            fatMassKg: fat,
            leanMassKg: lean,
            boneMassKg: bone,
            bodyFatPct: bodyFatPct
        )
    }

    @Test func leanGainWithStableFatIsMuscleGain() throws {
        let delta = try #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 20, lean: 57),
            current: scan("2026-02-01", total: 81.2, fat: 20.1, lean: 58.1)
        ))

        #expect(delta.verdict == .muscleGain)
        #expect(abs(delta.leanChangeKg - 1.1) < 0.000_001)
        #expect(delta.narrative.contains("Muscle gain"))
        #expect(delta.narrative.contains("fat held steady"))
    }

    @Test func missingTotalsFallBackToFatPlusLeanMass() throws {
        let delta = try #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", fat: 20, lean: 55, bone: 3, bodyFatPct: 25),
            current: scan("2026-02-01", fat: 18.5, lean: 56.5, bone: 2.8, bodyFatPct: 22.5)
        ))

        #expect(abs(delta.totalChangeKg) < 0.000_001)
        #expect(abs((delta.boneChangeKg ?? 0) + 0.2) < 0.000_001)
        #expect(abs((delta.bodyFatPctChange ?? 0) + 2.5) < 0.000_001)
        #expect(abs((delta.fatFractionOfChange ?? 0) - 0.5) < 0.000_001)
        #expect(delta.verdict == .recomposition)
    }

    @Test func subNoiseTissueMovementOmitsFatFraction() throws {
        let delta = try #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", fat: 20, lean: 55),
            current: scan("2026-01-15", fat: 20.02, lean: 54.98)
        ))

        #expect(delta.verdict == .stable)
        #expect(delta.fatFractionOfChange == nil)
        #expect(abs(delta.totalChangeKg) < 0.000_001)
    }

    @Test func agreeingEstimatesAreDirectionalAcrossDifferentWindows() throws {
        let delta = try #require(BodyCompositionAnalysis.scanDelta(
            previous: scan("2026-01-01", total: 80, fat: 22, lean: 55),
            current: scan("2026-04-01", total: 77, fat: 19, lean: 55)
        ))
        let reconciliation = try #require(BodyCompositionAnalysis.reconcile(
            delta: delta,
            estimatedDailyKcal: -300,
            trendWindowDays: 21
        ))

        #expect(!reconciliation.agrees)
        #expect(reconciliation.narrative.contains("Both point the same way"))
        #expect(reconciliation.narrative.contains("different spans"))
    }
}
