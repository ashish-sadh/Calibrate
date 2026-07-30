import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the design-665 nutrition-label FM migration.
// Cover the pure helpers (bounds + prompt + flag default). FM-backed
// extraction itself runs as Tier-3 in FoundationModelsExtractionEvalTests.

// MARK: - NutritionBounds — hallucination guard

@Test func bounds_passClean() {
    let r = FMNutritionResult(
        name: "Clif Bar", servingSize: "1 Bar (68g)",
        calories: 240, proteinG: 9, carbsG: 41, fatG: 5, fiberG: 4, sugarG: 21, sodiumMg: 200
    )
    #expect(NutritionBounds.violation(in: r) == nil)
}

@Test func bounds_rejectImpossibleCalories() {
    let r = FMNutritionResult(
        name: "Hallucination", servingSize: "1 g",
        calories: 12_000, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0
    )
    #expect(NutritionBounds.violation(in: r) == "calories")
}

@Test func bounds_rejectImpossibleProtein() {
    let r = FMNutritionResult(
        name: "Bad", servingSize: "1 serving",
        calories: 200, proteinG: 999, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0
    )
    #expect(NutritionBounds.violation(in: r) == "proteinG")
}

@Test func bounds_rejectImpossibleSodium() {
    let r = FMNutritionResult(
        name: "Bad", servingSize: "1 serving",
        calories: 200, proteinG: 5, carbsG: 5, fatG: 5, fiberG: 5, sugarG: 5, sodiumMg: 99_999
    )
    #expect(NutritionBounds.violation(in: r) == "sodiumMg")
}

@Test func bounds_zeroIsValid() {
    // A label that lists "0 g" everywhere is rare but legal — should not trigger
    let r = FMNutritionResult(
        name: "Water", servingSize: "240 mL",
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0
    )
    #expect(NutritionBounds.violation(in: r) == nil)
}

// MARK: - AtwaterCheck — energy/macro consistency guard

@Test func atwater_reportedAlooBhujiaBug() {
    // The 2026-07-30 operator report: barcode scan returned 130 kcal alongside
    // 8P/41C/47F per 100g. Atwater says 619; the packet label reads 624.
    #expect(!AtwaterCheck.isConsistent(stated: 130, proteinG: 8, carbsG: 41, fatG: 47))
    #expect(AtwaterCheck.reconciledCalories(stated: 130, proteinG: 8, carbsG: 41, fatG: 47) == 619)
}

@Test func atwater_realLabelDoublesReconcileToPacket() {
    // The actual per-100g values off the packet, unrounded, land on 624.
    let cal = AtwaterCheck.reconciledCalories(stated: 130, proteinG: 8.7, carbsG: 41.4, fatG: 47.1)
    #expect(cal == 624)
}

@Test func atwater_consistentSourceUntouched() {
    // A source that already agrees within tolerance is left exactly as-is —
    // we never rewrite a value we have no reason to distrust.
    #expect(AtwaterCheck.isConsistent(stated: 624, proteinG: 8.7, carbsG: 41.4, fatG: 47.1))
    #expect(AtwaterCheck.reconciledCalories(stated: 624, proteinG: 8.7, carbsG: 41.4, fatG: 47.1) == 624)
    // Rounding noise (Clif Bar: 240 vs computed 239) stays put.
    #expect(AtwaterCheck.reconciledCalories(stated: 240, proteinG: 9, carbsG: 41, fatG: 5, fiberG: 4) == 240)
}

@Test func atwater_highFiberNotFalselyRewritten() {
    // Psyllium-style: fiber is most of the carbs and near-non-caloric. Without
    // the fiber discount, computed (337) would wrongly overwrite a correct ~180.
    #expect(AtwaterCheck.isConsistent(stated: 180, proteinG: 2, carbsG: 80, fatG: 1, fiberG: 70))
    #expect(AtwaterCheck.reconciledCalories(stated: 180, proteinG: 2, carbsG: 80, fatG: 1, fiberG: 70) == 180)
}

@Test func atwater_missingEnergyFilledFromMacros() {
    // A row with real macros but a zero/absent energy field is inconsistent —
    // we fill the computed value rather than surface 0 kcal.
    #expect(!AtwaterCheck.isConsistent(stated: 0, proteinG: 8, carbsG: 41, fatG: 47))
    #expect(AtwaterCheck.reconciledCalories(stated: 0, proteinG: 8, carbsG: 41, fatG: 47) == 619)
}

@Test func atwater_noMacroSignalLeavesStatedAlone() {
    // Calories-only rows (a drink, an all-zero macro row) give nothing to check
    // against — the stated energy must pass through untouched.
    #expect(AtwaterCheck.isConsistent(stated: 90, proteinG: 0, carbsG: 0, fatG: 0))
    #expect(AtwaterCheck.reconciledCalories(stated: 90, proteinG: 0, carbsG: 0, fatG: 0) == 90)
}

@Test func atwater_overstatedEnergyAlsoCorrected() {
    // The guard is symmetric: a source that overstates energy is rewritten too.
    #expect(!AtwaterCheck.isConsistent(stated: 900, proteinG: 5, carbsG: 20, fatG: 3))
    #expect(AtwaterCheck.reconciledCalories(stated: 900, proteinG: 5, carbsG: 20, fatG: 3) == 127)
}

// MARK: - Feature flag default

@Test(.serialized) func fmNutritionExtractFlagBehavior() {
    // Single test instead of split — Swift Testing parallelizes by default
    // and the default + override paths share one UserDefaults key.
    let key = "drift_fm_nutrition_extract"
    defer { UserDefaults.standard.removeObject(forKey: key) }

    UserDefaults.standard.removeObject(forKey: key)
    #expect(Preferences.fmNutritionExtractEnabled == true,
            "Per design-665 the FM nutrition path defaults ON (kill-switch model)")

    Preferences.fmNutritionExtractEnabled = false
    #expect(Preferences.fmNutritionExtractEnabled == false,
            "Explicit off must persist")

    Preferences.fmNutritionExtractEnabled = true
    #expect(Preferences.fmNutritionExtractEnabled == true,
            "Explicit on must persist")
}

// MARK: - Prompt anchoring

@Test func prompt_asksForCanonicalUnits() {
    let p = NutritionExtractor.buildPrompt(for: "any")
    #expect(p.contains("kcal"))
    #expect(p.contains("grams"))
    #expect(p.contains("milligrams"))
}

@Test func prompt_handlesMultilingualLabels() {
    // The migration unlocks the non-English label case — pin the
    // multilingual instruction so a future prompt-refresh cycle doesn't drop it.
    let p = NutritionExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("any language") || p.contains("multilingual"))
    #expect(p.contains("spanish"))
    #expect(p.contains("hindi"))
}

@Test func prompt_treatsLessThanOneGramAsHalf() {
    // FDA labels say "<1 g" when value is between 0.5 and 1 — the rounded
    // half-gram is the most accurate single-value interpretation.
    let p = NutritionExtractor.buildPrompt(for: "any")
    #expect(p.contains("<1 g"))
    #expect(p.contains("0.5"))
}

@Test func prompt_includesInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let p = NutritionExtractor.buildPrompt(for: unique)
    #expect(p.contains(unique))
}
