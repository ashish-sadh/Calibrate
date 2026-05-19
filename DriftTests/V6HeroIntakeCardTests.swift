import XCTest
import SwiftUI
@testable import Drift

/// Tier-1 tests for `V6HeroIntakeCard` — the V6 Today-tab hero card chrome
/// (anatomy step 2 of `v6-today.jsx`). Pins the payload factory contract:
/// title string, pct-of-goal Int, ring array order, color tokens, and
/// NaN/inf/negative defensive handling. The SwiftUI view tree is dumb (just
/// renders payload fields), so the formatter is where bugs hide.
@MainActor
final class V6HeroIntakeCardTests: XCTestCase {

    // MARK: - Title text

    func testTitleSaysKcalLeftWhenUnderTarget() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 1450, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertTrue(p.titleText.hasSuffix(" kcal left"), "Expected '… kcal left', got \(p.titleText)")
        XCTAssertTrue(p.titleText.contains("550"), "Expected remaining 550 in title, got \(p.titleText)")
    }

    func testTitleSaysOnTargetWhenExactlyAtTarget() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 2000, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.titleText, "On target")
    }

    func testTitleSaysOnTargetWhenOverTarget() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 2400, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.titleText, "On target")
    }

    func testTitleRoundsRemainingToInteger() {
        // 1234.6 remaining → 1235 kcal left (rounded, not truncated).
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 765.4, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertTrue(p.titleText.contains("1,235") || p.titleText.contains("1235"),
                      "Expected rounded remaining 1235 in title, got \(p.titleText)")
    }

    // MARK: - Percentage of goal

    func testPctOfGoalRoundsHalfUp() {
        // 1500/2000 = 75% — no rounding ambiguity.
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 1500, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.pctOfGoal, 75)
    }

    func testPctOfGoalAllowsOvershootOver100() {
        // 2400/2000 = 120%. V6 design intentionally shows the overshoot
        // number so the user sees how far past goal they went.
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 2400, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.pctOfGoal, 120)
    }

    func testPctOfGoalReturnsZeroWhenTargetIsZero() {
        // Defensive: a 0-target macro shouldn't divide-by-zero or NaN-paint.
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 1450, kcalTarget: 0,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.pctOfGoal, 0)
    }

    // MARK: - NaN / inf / negative guards

    func testNanEatenFallsBackToZeroAndTreatsAsUnderTarget() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: .nan, kcalTarget: 2000,
            proteinEatenG: .nan, proteinTargetG: 150,
            fiberEatenG: .nan, fiberTargetG: 30,
            carbsEatenG: .nan, carbsTargetG: 220,
            fatEatenG: .nan, fatTargetG: 70
        )
        XCTAssertEqual(p.pctOfGoal, 0)
        XCTAssertEqual(p.kcalCenterValue, 0)
        XCTAssertTrue(p.titleText.contains("2,000") || p.titleText.contains("2000"),
                      "NaN eaten + target=2000 → 'X kcal left' should report full 2000, got \(p.titleText)")
        for ring in p.rings { XCTAssertEqual(ring.value, 0) }
    }

    func testInfiniteEatenFallsBackToZero() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: .infinity, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.pctOfGoal, 0)
        XCTAssertEqual(p.kcalCenterValue, 0)
    }

    func testNegativeEatenClampedToZero() {
        // A corrupt nutrition row with a negative gram count shouldn't paint
        // a phantom arc backwards.
        let p = V6HeroIntakeCard.payload(
            kcalEaten: -500, kcalTarget: 2000,
            proteinEatenG: -10, proteinTargetG: 150,
            fiberEatenG: 0, fiberTargetG: 30,
            carbsEatenG: 0, carbsTargetG: 220,
            fatEatenG: 0, fatTargetG: 70
        )
        XCTAssertEqual(p.pctOfGoal, 0)
        XCTAssertEqual(p.kcalCenterValue, 0)
        XCTAssertEqual(p.rings[0].value, 0, "kcal ring should clamp negative to 0")
        XCTAssertEqual(p.rings[1].value, 0, "protein ring should clamp negative to 0")
    }

    // MARK: - Ring array shape

    func testRingsArrayPreservesKcalProteinFiberOrder() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 1450, kcalTarget: 2000,
            proteinEatenG: 95, proteinTargetG: 150,
            fiberEatenG: 18, fiberTargetG: 30,
            carbsEatenG: 142, carbsTargetG: 220,
            fatEatenG: 48, fatTargetG: 70
        )
        XCTAssertEqual(p.rings.count, 3)
        XCTAssertEqual(p.rings[0].label, "kcal")
        XCTAssertEqual(p.rings[1].label, "protein")
        XCTAssertEqual(p.rings[2].label, "fiber")
        // V6 spec — V6Rings' identity discipline uses label as id, so the
        // order must be stable across recomputes.
        XCTAssertEqual(p.rings[0].value, 1450)
        XCTAssertEqual(p.rings[1].value, 95)
        XCTAssertEqual(p.rings[2].value, 18)
    }

    // MARK: - Carb + fat legend tokens

    func testCarbsLegendUsesV6CarbsColor() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 0, kcalTarget: 0,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 142, carbsTargetG: 220,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.carbsLegend.label, "carbs")
        XCTAssertEqual(p.carbsLegend.unit, "g")
        XCTAssertEqual(p.carbsLegend.value, 142)
        XCTAssertEqual(p.carbsLegend.target, 220)
        XCTAssertEqual(p.carbsLegend.color, Theme.V6.ringCarbs)
    }

    func testFatLegendUsesV6FatColor() {
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 0, kcalTarget: 0,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 48, fatTargetG: 70
        )
        XCTAssertEqual(p.fatLegend.label, "fat")
        XCTAssertEqual(p.fatLegend.unit, "g")
        XCTAssertEqual(p.fatLegend.value, 48)
        XCTAssertEqual(p.fatLegend.target, 70)
        XCTAssertEqual(p.fatLegend.color, Theme.V6.ringFat)
    }

    // MARK: - kcal center value & font step-down

    func testKcalCenterValueTruncatesToInteger() {
        // 1450.7 → 1450 (Int truncation, not rounding — center label sees
        // raw count, the rings see the precise double).
        let p = V6HeroIntakeCard.payload(
            kcalEaten: 1450.7, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0,
            fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0,
            fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(p.kcalCenterValue, 1450)
    }

    func testKcalCenterFontStepsDownFor4DigitDays() {
        let small = V6HeroIntakeCard.payload(
            kcalEaten: 850, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0, fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0, fatEatenG: 0, fatTargetG: 0
        )
        let big = V6HeroIntakeCard.payload(
            kcalEaten: 4500, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0, fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0, fatEatenG: 0, fatTargetG: 0
        )
        let huge = V6HeroIntakeCard.payload(
            kcalEaten: 12_000, kcalTarget: 2000,
            proteinEatenG: 0, proteinTargetG: 0, fiberEatenG: 0, fiberTargetG: 0,
            carbsEatenG: 0, carbsTargetG: 0, fatEatenG: 0, fatTargetG: 0
        )
        XCTAssertEqual(small.kcalCenterFontSize, 30, "<1000 kcal should use 30pt")
        XCTAssertEqual(big.kcalCenterFontSize, 26, "1000-9999 kcal should use 26pt")
        XCTAssertEqual(huge.kcalCenterFontSize, 22, "10000+ kcal should use 22pt")
    }
}
