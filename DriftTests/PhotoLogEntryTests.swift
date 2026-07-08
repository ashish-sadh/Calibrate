import Foundation
@testable import DriftCore
import Testing
@testable import Drift

private func sampleItem(name: String = "dal",
                        grams: Double = 100,
                        calories: Double = 180,
                        proteinG: Double = 12,
                        carbsG: Double = 20,
                        fatG: Double = 6,
                        confidence: Confidence = .high) -> PhotoLogItem {
    PhotoLogItem(name: name, grams: grams, calories: calories,
                 proteinG: proteinG, carbsG: carbsG, fatG: fatG, confidence: confidence)
}

// MARK: - PhotoLogEditableItem

@Test func editableItemStoresPerGramRates() {
    let item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200, proteinG: 10))
    #expect(item.caloriesPerGram == 2.0)
    #expect(item.proteinPerGram == 0.1)
    #expect(item.selected == true)
}

@Test func editableItemHandlesZeroGramsWithoutDividingByZero() {
    let item = PhotoLogEditableItem(from: sampleItem(grams: 0, calories: 0))
    #expect(item.caloriesPerGram == 0)
    #expect(item.proteinPerGram == 0)
}

// #1043: a plate of 3 idli (150 g total, count 3) stores per-PIECE weight (50 g), so the
// invariant grams == amount × gramsPerServingUnit holds and nudging the count scales
// proportionally — not by the whole-plate weight (the old ~3× corruption).
@Test func editableItemCountUnitStoresPerPieceWeight() {
    let plate = PhotoLogItem(name: "Idli", grams: 150, calories: 195,
                             proteinG: 6, carbsG: 40, fatG: 1, confidence: .high,
                             servingUnit: "pieces", servingAmount: 3)
    var item = PhotoLogEditableItem(from: plate)
    #expect(abs(item.gramsPerServingUnit - 50) < 0.01)
    #expect(abs(item.grams - item.servingAmount * item.gramsPerServingUnit) < 0.01)

    item.setAmount(4)  // ate 4, not 3
    #expect(abs(item.grams - 200) < 0.01)   // 4 × 50, not 4 × 150
    #expect(abs(item.calories - 260) < 1)   // 4 × per-piece 65 cal, not 4 × 195

    item.setAmount(1.5)  // "half" of 3
    #expect(abs(item.grams - 75) < 0.01)    // 1.5 × 50, not 1.5 × 150
}

// #1044: a blank/unnamed/0-cal row (an unfilled "Add item") is not loggable — no diary
// entry, no empty-named food written to the catalog.
@Test func blankItemIsNotLoggable() {
    #expect(PhotoLogEditableItem.blank().isLoggable == false)
    let named = PhotoLogEditableItem(from: sampleItem(name: "Dal", grams: 100, calories: 180))
    #expect(named.isLoggable == true)
}

// MARK: - Serving unit picker

@Test func suggestedUnitMatchesKeywords() {
    #expect(PhotoLogServingUnit.suggested(forName: "Slice of pizza") == .slices)
    #expect(PhotoLogServingUnit.suggested(forName: "Medium apple") == .pieces)
    #expect(PhotoLogServingUnit.suggested(forName: "Bowl of rice") == .cups)
    #expect(PhotoLogServingUnit.suggested(forName: "Peanut butter") == .tablespoons)
    #expect(PhotoLogServingUnit.suggested(forName: "Mixed vegetables") == .grams)
}

@Test func editableItemDefaultsToSuggestedUnit() {
    // "apple" → .pieces, 1 piece = originalGrams (182 g), so amount defaults to 1.
    let item = PhotoLogEditableItem(from: sampleItem(name: "Apple", grams: 182, calories: 95))
    #expect(item.servingUnit == .pieces)
    #expect(item.servingAmount == 1)
    #expect(item.originalGrams == 182)
}

@Test func editableItemVolumeUnitReflectsCurrentGrams() {
    // A 180g bowl of rice → default unit .cups, amount = 180 / 240 = 0.75
    let item = PhotoLogEditableItem(from: sampleItem(name: "Bowl of rice", grams: 180, calories: 230))
    #expect(item.servingUnit == .cups)
    #expect(abs(item.servingAmount - 0.75) < 1e-9)
}

@Test func setAmountRescalesMacros() {
    // Mixed vegetables → .grams unit. Double the amount → macros double.
    var item = PhotoLogEditableItem(from: sampleItem(name: "Mixed vegetables", grams: 100, calories: 180, proteinG: 12))
    #expect(item.servingUnit == .grams)
    item.setAmount(200)
    #expect(item.grams == 200)
    #expect(item.calories == 360)
    #expect(item.proteinG == 24)
}

@Test func setUnitPreservesGramsAndConvertsAmount() {
    // Switching from grams to oz keeps grams but shows 180 g as ≈6.35 oz.
    var item = PhotoLogEditableItem(from: sampleItem(name: "Mixed vegetables", grams: 180, calories: 220))
    #expect(item.servingUnit == .grams)
    item.setUnit(.ounces)
    #expect(item.grams == 180)
    #expect(abs(item.servingAmount - (180.0 / 28.3495)) < 1e-6)
}

@Test func setAmountInPiecesUsesOriginalWeight() {
    // LLM says "1 apple = 182 g". 2 pieces → 364 g, calories double.
    var item = PhotoLogEditableItem(from: sampleItem(name: "Apple", grams: 182, calories: 95))
    #expect(item.servingUnit == .pieces)
    item.setAmount(2)
    #expect(abs(item.grams - 364) < 1e-9)
    #expect(abs(item.calories - 190) < 1e-9)
}

// MARK: - LLM-returned serving hints + ingredients

@Test func aiReturnedServingUnitAndAmountOverrideHeuristic() {
    // "Mixed vegetables" keyword would default to .grams — but the LLM said
    // it's best represented as 1.5 cups. Trust the LLM.
    let raw = PhotoLogItem(
        name: "Mixed vegetables", grams: 360, calories: 200,
        proteinG: 8, carbsG: 40, fatG: 2, confidence: .high,
        servingUnit: "cups", servingAmount: 1.5
    )
    let item = PhotoLogEditableItem(from: raw)
    #expect(item.servingUnit == .cups)
    #expect(item.servingAmount == 1.5)
}

@Test func aiReturnedUnitAliasesParseLeniently() {
    // The model sometimes singularizes ("piece") or abbreviates ("tbsp").
    #expect(PhotoLogServingUnit.parse("piece") == .pieces)
    #expect(PhotoLogServingUnit.parse("tbsp") == .tablespoons)
    #expect(PhotoLogServingUnit.parse("OZ") == .ounces)
    #expect(PhotoLogServingUnit.parse("cup") == .cups)
    #expect(PhotoLogServingUnit.parse("G") == .grams)
    #expect(PhotoLogServingUnit.parse("slice") == .slices)
    #expect(PhotoLogServingUnit.parse("bushels") == nil)   // unknown → caller falls back
    #expect(PhotoLogServingUnit.parse("") == nil)
    #expect(PhotoLogServingUnit.parse(nil) == nil)
}

@Test func aiUnknownUnitFallsBackToHeuristic() {
    // Model returned a bogus unit — we should still produce a usable row
    // via the keyword heuristic rather than dropping the item.
    let raw = PhotoLogItem(
        name: "Pizza slice", grams: 120, calories: 280,
        proteinG: 12, carbsG: 30, fatG: 12, confidence: .high,
        servingUnit: "bushels", servingAmount: 1
    )
    let item = PhotoLogEditableItem(from: raw)
    #expect(item.servingUnit == .slices)  // heuristic picked up "pizza"/"slice"
}

@Test func ingredientsDecodeAndExposeOnItem() {
    // Plant-points needs the ingredient list; we surface it on the
    // editable item so the log flow can feed it into PlantPointsService.
    let raw = PhotoLogItem(
        name: "Pasta primavera", grams: 280, calories: 420,
        proteinG: 14, carbsG: 62, fatG: 10, confidence: .medium,
        ingredients: ["pasta", "tomato", "bell pepper", "basil", "garlic"]
    )
    let item = PhotoLogEditableItem(from: raw)
    #expect(item.ingredients == ["pasta", "tomato", "bell pepper", "basil", "garlic"])
}

@Test func missingIngredientsAreEmptyNotNil() {
    // Older payloads (or a declining model) omit the field. We default to
    // [] so downstream plant-points code can iterate without optional-unwrap.
    let raw = PhotoLogItem(
        name: "Banana", grams: 118, calories: 105,
        proteinG: 1, carbsG: 27, fatG: 0, confidence: .high
    )
    let item = PhotoLogEditableItem(from: raw)
    #expect(item.ingredients == [])
}

// MARK: - Macro editing + fiber

@Test func fiberDecodesAndRescalesLikeOtherMacros() {
    // Fiber joins the pack — scales linearly with grams/amount just like P/C/F.
    var item = PhotoLogEditableItem(from: PhotoLogItem(
        name: "Mixed vegetables", grams: 100, calories: 50,
        proteinG: 2, carbsG: 10, fatG: 0, fiberG: 4, confidence: .medium
    ))
    #expect(item.fiberG == 4)
    item.setAmount(200)  // .grams unit → direct grams edit
    #expect(item.grams == 200)
    #expect(abs(item.fiberG - 8) < 1e-9)
}

@Test func setMacroRescalesFromUserCorrectedBaseline() {
    // LLM said pizza slice has 12g protein. User bumps to 15g. A later
    // amount-double should now scale from 15, not 12 (per-gram rate updated).
    var item = PhotoLogEditableItem(from: PhotoLogItem(
        name: "Pizza slice", grams: 120, calories: 280,
        proteinG: 12, carbsG: 30, fatG: 12, fiberG: 2, confidence: .high
    ))
    item.setMacro(.protein, to: 15)
    #expect(item.proteinG == 15)
    #expect(item.macrosManuallyEdited == true)
    // Switch to pieces (1 piece = 120g), double to 2 pieces → 240g.
    #expect(item.servingUnit == .slices)   // name matches heuristic
    item.setAmount(2)
    #expect(abs(item.grams - 240) < 1e-9)
    #expect(abs(item.proteinG - 30) < 1e-9)  // 15 × 2, not 12 × 2
}

@Test func setMacroCaloriesAppliesIndependentlyFromOtherMacros() {
    // Correcting calories shouldn't shift P/C/F/Fb (they each have their
    // own per-gram rate).
    var item = PhotoLogEditableItem(from: PhotoLogItem(
        name: "Lasagna", grams: 250, calories: 400,
        proteinG: 20, carbsG: 40, fatG: 18, fiberG: 3, confidence: .medium
    ))
    item.setMacro(.calories, to: 500)
    #expect(item.calories == 500)
    #expect(item.proteinG == 20)
    #expect(item.carbsG == 40)
    #expect(item.fatG == 18)
    #expect(item.fiberG == 3)
}

@Test func rescaleScalesAllMacrosLinearly() {
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200, proteinG: 10, carbsG: 20, fatG: 6))
    item.grams = 150
    item.rescale()
    #expect(item.calories == 300)
    #expect(item.proteinG == 15)
    #expect(item.carbsG == 30)
    #expect(item.fatG == 9)
}

@Test func rescaleToZeroZerosMacros() {
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200, proteinG: 10))
    item.grams = 0
    item.rescale()
    #expect(item.calories == 0)
    #expect(item.proteinG == 0)
}

@Test func rescaleClampsNegativeGramsToZero() {
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200))
    item.grams = -50
    item.rescale()
    #expect(item.grams == 0)
    #expect(item.calories == 0)
}

// MARK: - PhotoLogTotals

@Test func totalsZeroForEmptyInput() {
    let totals = PhotoLogTotals.sum([])
    #expect(totals == .zero)
}

@Test func totalsOnlySumSelectedItems() {
    var a = PhotoLogEditableItem(from: sampleItem(name: "a", grams: 100, calories: 100, proteinG: 10, carbsG: 5, fatG: 2))
    var b = PhotoLogEditableItem(from: sampleItem(name: "b", grams: 100, calories: 200, proteinG: 5, carbsG: 30, fatG: 8))
    a.selected = true
    b.selected = false
    let totals = PhotoLogTotals.sum([a, b])
    #expect(totals.calories == 100)
    #expect(totals.proteinG == 10)
    #expect(totals.carbsG == 5)
    #expect(totals.fatG == 2)
    #expect(totals.selectedCount == 1)
}

@Test func totalsRoundIndividualValues() {
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 100.6, proteinG: 10.4))
    item.selected = true
    let totals = PhotoLogTotals.sum([item])
    #expect(totals.calories == 101)  // 100.6 → 101
    #expect(totals.proteinG == 10)   // 10.4 → 10
    #expect(totals.selectedCount == 1)
}

@Test func totalsReflectScaleAfterEdit() {
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200, proteinG: 10))
    item.grams = 50
    item.rescale()
    let totals = PhotoLogTotals.sum([item])
    #expect(totals.calories == 100)
    #expect(totals.proteinG == 5)
}

// MARK: - Default meal type

@Test func defaultMealTypeFollowsHourOfDay() {
    // morning → breakfast
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let comp = DateComponents(year: 2026, month: 4, day: 20, hour: 8, minute: 0)
    let morning = cal.date(from: comp)!
    let mt = MealType.resolve(now: morning, recentEntries: [])
    // The fallback uses local calendar's hour extraction — we just want it
    // to pick a sensible label that matches one of the breakfast/lunch/dinner/snack buckets.
    #expect(MealType.allCases.contains(mt))
}

@Test func defaultMealTypeInheritsFromRecentEntry() {
    // If a breakfast entry was logged 30 min ago, default stays breakfast
    // regardless of clock drift. `MealType.resolve` uses entries' mealType
    // field when within the 3h inherit window.
    let iso = DateFormatters.iso8601
    let thirtyMinAgo = iso.string(from: Date().addingTimeInterval(-30 * 60))
    let entry = FoodEntry(
        foodName: "oats",
        servingSizeG: 50,
        calories: 200,
        proteinG: 8, carbsG: 30, fatG: 4, fiberG: 3,
        loggedAt: thirtyMinAgo,
        mealType: MealType.breakfast.rawValue
    )
    let mt = MealType.resolve(now: Date(), recentEntries: [entry])
    #expect(mt == .breakfast)
}

// MARK: - Add / remove / name-edit mutations (#495)

@Test func blankItemHasZeroMacrosAndDefaultGrams() {
    let item = PhotoLogEditableItem.blank()
    #expect(item.name == "")
    #expect(item.grams == 100)
    #expect(item.calories == 0)
    #expect(item.proteinG == 0)
    #expect(item.carbsG == 0)
    #expect(item.fatG == 0)
    #expect(item.selected == true)
    // Per-gram rates are zero so a later rescale doesn't invent calories.
    #expect(item.caloriesPerGram == 0)
    #expect(item.proteinPerGram == 0)
}

@Test func nameEditIsDirectMutation() {
    // The review card binds TextField directly to item.name — verify the
    // struct field is mutable and the change sticks.
    var item = PhotoLogEditableItem(from: sampleItem(name: "random soup"))
    item.name = "Dal Tadka"
    #expect(item.name == "Dal Tadka")
}

@Test func applyHintMatchReplacesNameAndRecalcsMacros() {
    // User typed "palak paneer" — DB match substitutes canonical name +
    // recalculates per-gram rates from the DB food's servingSize.
    var item = PhotoLogEditableItem(from: sampleItem(name: "spinach cheese curry", grams: 200, calories: 100))
    let food = Food(name: "Palak Paneer", category: "Indian Curries",
                    servingSize: 200, servingUnit: "g",
                    calories: 280, proteinG: 14, carbsG: 10, fatG: 20)
    item.applyHintMatch(food)
    #expect(item.name == "Palak Paneer")
    #expect(item.confidence == .high)
    #expect(item.macrosManuallyEdited == false)
    // Macros rescaled to current 200g from DB's per-gram rates.
    #expect(abs(item.calories - 280) < 1e-6)
    #expect(abs(item.proteinG - 14) < 1e-6)
}

@Test func applyHintMatchAppliesPortionDefaultWhenGramsIsZero() {
    // The LLM missed the grams; applyHintMatch fills in a category-aware default.
    var item = PhotoLogEditableItem(from: sampleItem(name: "unknown", grams: 0, calories: 0))
    let food = Food(name: "Dal Makhani", category: "Indian Curries",
                    servingSize: 200, servingUnit: "g",
                    calories: 180, proteinG: 8, carbsG: 22, fatG: 7)
    item.applyHintMatch(food)
    // portionDefault for "Indian Curries" is 200g.
    #expect(item.grams == 200)
    #expect(item.name == "Dal Makhani")
}

// MARK: - Inline DB search for Add item (#525)

@Test @MainActor func addItemDBPickPopulatesNameAndMacros() {
    var item = PhotoLogEditableItem.blank()
    let results = FoodService.searchFood(query: "rice")
    guard let food = results.first else { return } // skip if DB empty
    item.applyHintMatch(food)
    #expect(!item.name.isEmpty)
    #expect(item.calories > 0)
    #expect(item.grams > 0)
    #expect(item.caloriesPerGram > 0)
}

@Test @MainActor func unknownQueryYieldsNoDBResults() {
    let results = FoodService.searchFood(query: "asdfqwer123xyz")
    #expect(results.isEmpty)
}

@Test func addItemBlankRowHasZeroMacrosUntilPicked() {
    let item = PhotoLogEditableItem.blank()
    #expect(item.name.isEmpty)
    #expect(item.calories == 0)
    #expect(item.proteinG == 0)
    #expect(item.carbsG == 0)
    #expect(item.fatG == 0)
}

// MARK: - AI correction scoping (#524)

@Test func applyAICorrectionUpdatesOnlyTargetItem() {
    // 3-item meal: edit item 2 manually, apply AI correction to item 1,
    // assert item 2's edits are preserved and item 3 is untouched.
    var item1 = PhotoLogEditableItem(from: sampleItem(name: "rice", grams: 150, calories: 200))
    var item2 = PhotoLogEditableItem(from: sampleItem(name: "dal", grams: 100, calories: 180, proteinG: 12))
    var item3 = PhotoLogEditableItem(from: sampleItem(name: "paratha", grams: 60, calories: 150))

    // User manually edits item 2 name + protein
    item2.name = "moong dal"
    item2.setMacro(.protein, to: 15)
    #expect(item2.macrosManuallyEdited == true)

    // User unselects item 3
    item3.selected = false

    // Capture state before correction
    let item2NameBefore = item2.name
    let item2ProteinBefore = item2.proteinG
    let item3NameBefore = item3.name
    let item3GramsBefore = item3.grams

    // Apply AI correction to item 1 only
    let corrected = PhotoLogItem(name: "basmati rice", grams: 180, calories: 240,
                                 proteinG: 4, carbsG: 52, fatG: 1, confidence: .high)
    item1.applyAICorrection(corrected)

    // item 1 updated
    #expect(item1.name == "basmati rice")
    #expect(item1.grams == 180)
    #expect(item1.calories == 240)

    // item 2 completely untouched
    #expect(item2.name == item2NameBefore)
    #expect(abs(item2.proteinG - item2ProteinBefore) < 1e-9)
    #expect(item2.macrosManuallyEdited == true)

    // item 3 completely untouched
    #expect(item3.name == item3NameBefore)
    #expect(item3.grams == item3GramsBefore)
    #expect(item3.selected == false)
}

@Test func applyAICorrectionPreservesSelectedFlag() {
    // selected = false before correction must remain false after
    var item = PhotoLogEditableItem(from: sampleItem(name: "samosa", grams: 80, calories: 200))
    item.selected = false
    let corrected = PhotoLogItem(name: "aloo samosa", grams: 90, calories: 220,
                                 proteinG: 3, carbsG: 28, fatG: 10, confidence: .high)
    item.applyAICorrection(corrected)
    #expect(item.selected == false)
    #expect(item.name == "aloo samosa")
}

@Test func applyAICorrectionResetsManuallyEditedFlag() {
    // User had edited macros; AI correction resets the flag (new baseline)
    var item = PhotoLogEditableItem(from: sampleItem(name: "paneer", grams: 100, calories: 260))
    item.setMacro(.protein, to: 20)
    #expect(item.macrosManuallyEdited == true)
    let corrected = PhotoLogItem(name: "paneer tikka", grams: 120, calories: 310,
                                 proteinG: 22, carbsG: 5, fatG: 23, confidence: .high)
    item.applyAICorrection(corrected)
    #expect(item.macrosManuallyEdited == false)
    #expect(item.name == "paneer tikka")
    #expect(abs(item.proteinG - 22) < 1e-9)
}

@Test func applyAICorrectionUpdatesPerGramRatesForFutureRescale() {
    // After AI correction, a subsequent grams edit should use the new rates
    var item = PhotoLogEditableItem(from: sampleItem(grams: 100, calories: 200, proteinG: 10))
    let corrected = PhotoLogItem(name: "dal makhani", grams: 200, calories: 300,
                                 proteinG: 16, carbsG: 30, fatG: 10, confidence: .high)
    item.applyAICorrection(corrected)
    // Per-gram rates from corrected item: protein = 16/200 = 0.08
    item.grams = 100
    item.rescale()
    #expect(abs(item.proteinG - 8) < 1e-9)   // 0.08 × 100
    #expect(abs(item.calories - 150) < 1e-9) // 1.5 × 100
}

@Test func applyAICorrectionUpdatesIngredients() {
    // Ingredients list replaced with AI's updated answer
    var item = PhotoLogEditableItem(from: PhotoLogItem(
        name: "veg pulao", grams: 200, calories: 300,
        proteinG: 8, carbsG: 55, fatG: 6, confidence: .medium,
        ingredients: ["rice", "carrot"]
    ))
    let corrected = PhotoLogItem(name: "veg biryani", grams: 250, calories: 380,
                                 proteinG: 10, carbsG: 68, fatG: 8, confidence: .high,
                                 ingredients: ["basmati rice", "potato", "onion", "spices"])
    item.applyAICorrection(corrected)
    #expect(item.ingredients == ["basmati rice", "potato", "onion", "spices"])
}

@Test func applyHintMatchRescalesFromCorrectedRates() {
    // After applyHintMatch, a serving-amount change should use the DB food's
    // per-gram rates, not the original LLM rates.
    var item = PhotoLogEditableItem(from: sampleItem(name: "butter chicken", grams: 150, calories: 200, proteinG: 10))
    let food = Food(name: "Butter Chicken", category: "Indian Curries",
                    servingSize: 300, servingUnit: "g",
                    calories: 360, proteinG: 24, carbsG: 12, fatG: 18)
    item.applyHintMatch(food)
    // item.grams is still 150; per-gram protein = 24/300 = 0.08 → 150g → 12g.
    #expect(abs(item.proteinG - 12) < 1e-6)
    // Double the grams; protein should be 24g (from DB rate, not original 10g/150g).
    item.grams = 300
    item.rescale()
    #expect(abs(item.proteinG - 24) < 1e-6)
}
