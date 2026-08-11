import Foundation
@testable import DriftCore
import Testing

/// #282 — plain `Int()` truncation on small fiber values made 1.5g → "1g" and
/// 0.6g → "0g", which looked like data loss. These tests lock the
/// one-decimal-for-sub-10g behaviour so we don't regress back to a bare cast.

@Test func fiberZeroShowsZero() {
    #expect(MacroFormatter.fiber(0) == "0")
}

@Test func fiberWholeUnderTenShowsInteger() {
    #expect(MacroFormatter.fiber(1) == "1")
    #expect(MacroFormatter.fiber(3) == "3")
    #expect(MacroFormatter.fiber(9) == "9")
}

@Test func fiberFractionalUnderTenShowsOneDecimal() {
    #expect(MacroFormatter.fiber(1.5) == "1.5")
    #expect(MacroFormatter.fiber(2.3) == "2.3")
    #expect(MacroFormatter.fiber(0.5) == "0.5")
}

@Test func fiberSmallNonZeroRoundsToOneDecimal() {
    // 0.6 rounds to 0.6 (shown), not 0 — the original truncation bug.
    #expect(MacroFormatter.fiber(0.6) == "0.6")
    // 0.04 rounds down to 0.0, collapsed to "0".
    #expect(MacroFormatter.fiber(0.04) == "0")
}

@Test func fiberTenOrAboveShowsRoundedInteger() {
    #expect(MacroFormatter.fiber(10) == "10")
    #expect(MacroFormatter.fiber(12.4) == "12")
    #expect(MacroFormatter.fiber(12.6) == "13")
    #expect(MacroFormatter.fiber(25) == "25")
}

/// Regression for #282 specifically: user logs 75g strawberry, fiber should
/// render as "1.5g", not "0g" or "1g".
@Test func fiberSeventyFiveGramStrawberryShowsOnePointFive() {
    let fiberPerServing: Double = 3    // per 150g
    let servings: Double = 75.0 / 150.0
    let total = fiberPerServing * servings
    #expect(MacroFormatter.fiber(total) == "1.5")
}

// MARK: - PhotoLogItem.reviewSummary (#1218)

/// The same truncation defect as #282, one surface over: the AI review rows
/// (Describe / Snap / Coach) built their macro line with a bare `Int()`, so
/// Egg ×2's real 0.8g of carbs rendered "C 0" on Android while the identical
/// food read "1g" on the iPhone card. Round, then clamp.

private func eggPairItem(
    calories: Double = 144.6,
    grams: Double = 100.4,
    proteinG: Double = 12.6,
    carbsG: Double = 0.8,
    fatG: Double = 9.6
) -> PhotoLogItem {
    PhotoLogItem(name: "Egg ×2", grams: grams, calories: calories,
                 proteinG: proteinG, carbsG: carbsG, fatG: fatG,
                 confidence: .high)
}

@Test func reviewSummaryRoundsRatherThanTruncates() {
    #expect(eggPairItem().reviewSummary == "145 cal · 100g · P 13 C 1 F 10")
}

/// A food that genuinely has no carbs must still read "C 0" — the fix is
/// rounding, not a blanket floor of 1.
@Test func reviewSummaryKeepsTrueZeroAtZero() {
    let item = eggPairItem(carbsG: 0)
    #expect(item.reviewSummary.contains(" C 0 "))
}

/// Rounding is half-up at .5 and still rounds DOWN below it, so the line
/// never over-reports either.
@Test func reviewSummaryRoundsDownBelowHalf() {
    let item = eggPairItem(calories: 144.4, grams: 100.5, proteinG: 12.4, carbsG: 0.4, fatG: 9.5)
    #expect(item.reviewSummary == "144 cal · 101g · P 12 C 0 F 10")
}

/// Model JSON is unvalidated input: `Int()` on NaN/±∞ is an uncatchable trap
/// (#1036). `safeInt` clamps — NaN to 0, +∞ to `Int.max` — so a garbage
/// response renders something ugly instead of killing the review sheet.
@Test func reviewSummarySurvivesNaNAndInfinity() {
    let nanItem = eggPairItem(calories: .nan, carbsG: .nan)
    #expect(nanItem.reviewSummary == "0 cal · 100g · P 13 C 0 F 10")

    let infItem = eggPairItem(calories: .infinity)
    #expect(infItem.reviewSummary == "\(Int.max) cal · 100g · P 13 C 1 F 10")
}

/// Telemetry rounds the same way, so a recorded turn agrees with the digits
/// the user actually saw on the row.
@Test func telemetrySummaryRoundsLikeTheRow() {
    #expect(eggPairItem().telemetrySummary == "Egg ×2 · 145cal · 100g")
}
