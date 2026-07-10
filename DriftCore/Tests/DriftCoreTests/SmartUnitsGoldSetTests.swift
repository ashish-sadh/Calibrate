import XCTest
@testable import DriftCore

/// Isolated gold set for FoodUnit.smartUnits — sprint task #161.
/// Tests that 20+ foods return the correct primary serving unit.
/// Fully deterministic (pure function, no LLM, no DB). Runs in <1s.
///
/// Run: xcodebuild test -only-testing:'DriftTests/SmartUnitsGoldSetTests'
final class SmartUnitsGoldSetTests: XCTestCase {

    private func food(_ name: String, size: Double = 100) -> Food {
        Food(name: name, category: "Test", servingSize: size, servingUnit: "g", calories: 100)
    }

    private func primaryUnit(for name: String, size: Double = 100) -> String {
        FoodUnit.smartUnits(for: food(name, size: size)).first?.label ?? ""
    }

    // MARK: - Countable Items (piece/named unit)

    func testEggsGetEggUnit() {
        let eggFoods = [
            ("Egg (whole, boiled)", 50.0),
            ("Egg (fried)", 50.0),
            ("Egg (poached)", 50.0),
            ("Egg white", 33.0),
            ("Large Egg", 50.0),
        ]
        var correct = 0
        for (name, size) in eggFoods {
            let unit = primaryUnit(for: name, size: size)
            if unit == "egg" { correct += 1 }
            else { print("MISS (egg unit): '\(name)' → '\(unit)'") }
        }
        print("📊 Egg unit: \(correct)/\(eggFoods.count)")
        XCTAssertEqual(correct, eggFoods.count, "All egg entries should get 'egg' as primary unit")
    }

    func testIndianFlatbreadsGetPieceUnit() {
        let flatbreads = ["Roti", "Chapati", "Naan", "Paratha", "Puri", "Bhatura", "Phulka", "Thepla"]
        var correct = 0
        for name in flatbreads {
            let unit = primaryUnit(for: name)
            if unit == "piece" { correct += 1 }
            else { print("MISS (flatbread unit): '\(name)' → '\(unit)'") }
        }
        print("📊 Flatbread piece unit: \(correct)/\(flatbreads.count)")
        XCTAssertEqual(correct, flatbreads.count, "All flatbreads should get 'piece' as primary unit")
    }

    func testIndianSnacksGetPieceUnit() {
        let snacks = ["Idli", "Dosa", "Vada", "Samosa", "Pakora", "Momo", "Dhokla"]
        var correct = 0
        for name in snacks {
            let unit = primaryUnit(for: name)
            if unit == "piece" { correct += 1 }
            else { print("MISS (snack unit): '\(name)' → '\(unit)'") }
        }
        print("📊 Indian snack piece unit: \(correct)/\(snacks.count)")
        XCTAssertEqual(correct, snacks.count, "Indian snack pieces should get 'piece' as primary unit")
    }

    // MARK: - Oils & Fats (tbsp primary)

    func testOilsGetTbspUnit() {
        let oils = ["Olive Oil", "Coconut Oil", "Sunflower Oil", "Vegetable Oil", "Sesame Oil"]
        var correct = 0
        for name in oils {
            let unit = primaryUnit(for: name, size: 14)
            if unit == "tbsp" { correct += 1 }
            else { print("MISS (oil unit): '\(name)' → '\(unit)'") }
        }
        print("📊 Oil tbsp unit: \(correct)/\(oils.count)")
        XCTAssertEqual(correct, oils.count, "Oils should get 'tbsp' as primary unit")
    }

    func testButterGetsTbspUnit() {
        // "butter" word-boundary matches the tbsp rule (excludes "butter chicken", "peanut butter")
        let unit = primaryUnit(for: "Butter (unsalted)", size: 14)
        XCTAssertEqual(unit, "tbsp", "Butter should get 'tbsp' as primary unit")
    }

    func testGheeGetsTbspUnit() {
        let unit = primaryUnit(for: "Ghee", size: 14)
        XCTAssertEqual(unit, "tbsp", "Ghee should get 'tbsp' as primary unit")
    }

    // MARK: - Protein Powders (scoop in unit list)

    func testProteinPowderIncludesScoopUnit() {
        let powders = [
            "Whey Protein Powder",
            "ON Gold Standard Whey",
            "Casein Protein",
            "Creatine Monohydrate",
        ]
        for name in powders {
            let units = FoodUnit.smartUnits(for: food(name, size: 30))
            let hasScoop = units.contains(where: { $0.label == "scoop" })
            XCTAssertTrue(hasScoop, "'\(name)' should include 'scoop' unit, got: \(units.map(\.label))")
        }
    }

    // MARK: - Liquids (ml in unit list)

    func testLiquidsIncludeMlUnit() {
        let liquids = ["Milk (whole)", "Orange Juice", "Buttermilk", "Coconut Water", "Bone Broth"]
        for name in liquids {
            let units = FoodUnit.smartUnits(for: food(name, size: 240))
            let hasMl = units.contains(where: { $0.label == "ml" })
            XCTAssertTrue(hasMl, "'\(name)' should include 'ml' unit, got: \(units.map(\.label))")
        }
    }

    // MARK: - Grains & Legumes (cup in unit list)

    func testGrainsIncludeCupUnit() {
        let grains = ["Basmati Rice", "Oats (dry)", "Moong Dal", "Chickpeas (cooked)", "Quinoa"]
        for name in grains {
            let units = FoodUnit.smartUnits(for: food(name, size: 200))
            let hasCup = units.contains(where: { $0.label == "cup" })
            XCTAssertTrue(hasCup, "'\(name)' should include 'cup' unit, got: \(units.map(\.label))")
        }
    }

    // MARK: - Nuts (named unit per nut type)

    func testAlmondsGetAlmondUnit() {
        let units = FoodUnit.smartUnits(for: food("Almonds (raw)", size: 28))
        let hasAlmond = units.contains(where: { $0.label == "almond" })
        XCTAssertTrue(hasAlmond, "Almonds should include 'almond' count unit")
    }

    func testCashewsGetCashewUnit() {
        let units = FoodUnit.smartUnits(for: food("Cashews (roasted)", size: 28))
        let hasCashew = units.contains(where: { $0.label == "cashew" })
        XCTAssertTrue(hasCashew, "Cashews should include 'cashew' count unit")
    }

    // #1010: nuts default to a concrete "handful", not a vague "serving".
    func testNutsDefaultToHandful() {
        XCTAssertEqual(primaryUnit(for: "Almonds (raw)", size: 28), "handful")
        XCTAssertEqual(primaryUnit(for: "Cashews (roasted)", size: 28), "handful")
        XCTAssertEqual(primaryUnit(for: "Walnuts", size: 28), "handful")
    }

    // #1011: peanut butter tbsp is ~16 g (a real tablespoon), matching almond butter.
    func testPeanutButterTbspIs16g() {
        let tbsp = FoodUnit.smartUnits(for: food("Peanut Butter", size: 32)).first(where: { $0.label == "tbsp" })
        XCTAssertEqual(tbsp?.gramsEquivalent, 16, "PB tbsp must be ~16g, not 32g")
    }

    // MARK: - #1012: seeded serving_unit drives the default on a keyword miss

    func testSeededServingUnitDrivesDefaultOnKeywordMiss() {
        // A nonsense name that hits no keyword rule; its seeded 'bowl' unit should win.
        let f = Food(name: "Zzyxw Blorptn", category: "Test", servingSize: 300,
                     servingUnit: "bowl", calories: 400)
        XCTAssertEqual(FoodUnit.smartUnits(for: f).first?.label, "bowl")
    }

    func testGramServingUnitKeepsGenericDefaultOnKeywordMiss() {
        // 'g' serving_unit → no synthesis; keyword miss keeps the generic 'serving'.
        let f = Food(name: "Zzyxw Blorptn", category: "Test", servingSize: 100,
                     servingUnit: "g", calories: 100)
        XCTAssertEqual(FoodUnit.smartUnits(for: f).first?.label, "serving")
    }

    func testUnitFromSeededServingUnitNormalizesAndGuards() {
        XCTAssertEqual(FoodUnit.unitFromSeededServingUnit("1 cup", servingSize: 240)?.label, "cup")
        XCTAssertEqual(FoodUnit.unitFromSeededServingUnit("slices", servingSize: 30)?.label, "slice")
        XCTAssertNil(FoodUnit.unitFromSeededServingUnit("g", servingSize: 100))
        XCTAssertNil(FoodUnit.unitFromSeededServingUnit("6 wings", servingSize: 180))  // multi-word/digit junk
        XCTAssertNil(FoodUnit.unitFromSeededServingUnit("cup", servingSize: 3))        // count-convention (tiny ss)
    }

    // #1014: paneer is a solid — defaults to grams, not "1 cup".
    func testPaneerDefaultsToGramsNotCup() {
        let units = FoodUnit.smartUnits(for: food("Paneer", size: 150))
        XCTAssertEqual(units.first?.label, "g")
        XCTAssertFalse(units.contains { $0.label == "cup" }, "paneer should not offer a cup unit")
    }

    // #1014: a cup reflects the food's seeded serving, not a fixed 240/245 (~20% over).
    func testCupWeightReconcilesToServingSize() {
        let cup = FoodUnit.smartUnits(for: food("Curd (plain)", size: 200)).first(where: { $0.label == "cup" })
        XCTAssertEqual(cup?.gramsEquivalent, 200, "1 cup of curd = its 200 g serving, not 245")
    }

    // #1049: ml-seeded liquids default to a human measure (cup/can), not raw ml.
    func testLiquidCoffeeDefaultsToCup() {
        let coffee = Food(name: "Coffee (with milk)", category: "Beverages", servingSize: 240, servingUnit: "ml", calories: 60)
        XCTAssertEqual(FoodUnit.smartUnits(for: coffee).first?.label, "cup")
    }

    func testCanSizedLiquidDefaultsToCan() {
        let soda = Food(name: "Cola", category: "Beverages", servingSize: 355, servingUnit: "ml", calories: 140)
        XCTAssertEqual(FoodUnit.smartUnits(for: soda).first?.label, "can")
    }

    func testNonStandardLiquidNotForcedToCup() {
        // 200 ml is >10% from any standard measure → keeps ml/generic, no weird "1.04 cup".
        let juice = Food(name: "Juice", category: "Beverages", servingSize: 200, servingUnit: "ml", calories: 90)
        XCTAssertNotEqual(FoodUnit.smartUnits(for: juice).first?.label, "cup")
    }

    // #1048: a scanned beverage's default amount + primary unit logs the real serving, not ~0
    // (the barcode sheet previously hardcoded amount "1" on an ml unit → ~0.4 cal).
    func testBeverageDefaultAmountGivesRealCalories() {
        // 330 ml can → primary "can" (330 g), defaultAmount "1" → 1 × 330 / 330 = full serving.
        let soda = Food(name: "Cola", category: "Beverages", servingSize: 330, servingUnit: "ml", calories: 139)
        let primary = FoodUnit.smartUnits(for: soda).first!
        let amount = Double(FoodUnit.defaultAmount(for: soda)) ?? 0
        let multiplier = (amount * primary.gramsEquivalent) / soda.servingSize
        XCTAssertEqual(soda.calories * multiplier, 139, accuracy: 1)

        // A truly non-standard ml size stays ml-primary; defaultAmount prefills the serving,
        // not 1 — so it still logs the real calories, not 1 ml worth.
        let odd = Food(name: "Tonic", category: "Beverages", servingSize: 187, servingUnit: "ml", calories: 75)
        let oddPrimary = FoodUnit.smartUnits(for: odd).first!
        let oddAmount = Double(FoodUnit.defaultAmount(for: odd)) ?? 0
        XCTAssertEqual(odd.calories * (oddAmount * oddPrimary.gramsEquivalent) / odd.servingSize, 75, accuracy: 1)
    }

    // MARK: - Specific Protein & Vegetable Units

    func testMeatPortionsGetPieceUnit() {
        // Named cuts return "piece" — single-serve portions
        XCTAssertEqual(primaryUnit(for: "Chicken Breast (grilled)", size: 150), "piece")
        XCTAssertEqual(primaryUnit(for: "Salmon Fillet", size: 150), "piece")
        XCTAssertEqual(primaryUnit(for: "Chicken Thigh (roasted)", size: 100), "piece")
    }

    func testCookedVegetablesGetCupUnit() {
        // Cooked vegetables are measured by cup, not piece or grams
        XCTAssertEqual(primaryUnit(for: "Broccoli (steamed)", size: 90), "cup")
        XCTAssertEqual(primaryUnit(for: "Cauliflower (roasted)", size: 90), "cup")
    }

    // MARK: - Unit List Completeness

    func testAllFoodsHaveAtLeastOneUnit() {
        let foods: [Food] = [
            food("Egg (boiled)", size: 50),
            food("Olive Oil", size: 14),
            food("Basmati Rice", size: 200),
            food("Chicken Breast", size: 150),
            food("Whey Protein Powder", size: 30),
            food("Milk (whole)", size: 240),
            food("Roti", size: 40),
            food("Almonds", size: 28),
            food("Banana", size: 120),
            food("Ghee", size: 14),
        ]
        for f in foods {
            let units = FoodUnit.smartUnits(for: f)
            XCTAssertFalse(units.isEmpty, "'\(f.name)' should have at least one serving unit")
        }
    }

    func testGramsAlwaysPresentForNonCountables() {
        // Non-countable solids must always include grams as a fallback
        let solids = [
            food("Chicken Breast (grilled)", size: 150),
            food("Basmati Rice", size: 200),
        ]
        for f in solids {
            let units = FoodUnit.smartUnits(for: f)
            let hasGrams = units.contains(where: { $0.label == "g" })
            XCTAssertTrue(hasGrams, "'\(f.name)' should always include 'g' as a unit option")
        }
    }

    // MARK: - Branded bars (bug #278: Kind bar scanner defaulted to 4ml)

    func testKindBarBrandResolvesToPiece() {
        // OFF returns "Dark Chocolate Nuts & Sea Salt" with brands "KIND" — the word "bar"
        // is NOT in product_name. Must still resolve to a per-piece unit, not ml/serving.
        let units = FoodUnit.smartUnits(for: food("Dark Chocolate Nuts & Sea Salt - KIND", size: 40))
        XCTAssertEqual(units.first?.label, "piece",
                       "KIND bar product without 'bar' in name should get 'piece' primary; got \(units.map(\.label))")
        XCTAssertFalse(units.contains(where: { $0.label == "ml" }),
                       "KIND chocolate bar must not include 'ml' unit; got \(units.map(\.label))")
        XCTAssertFalse(units.contains(where: { $0.label == "fl oz" }),
                       "KIND chocolate bar must not include 'fl oz' unit; got \(units.map(\.label))")
    }

    func testClifAndQuestBrandedBarsResolveToPiece() {
        // Other branded bars where OFF omits "bar" from product_name.
        // Flavors chosen to avoid hitting earlier fruit (banana/apple) or peanut-butter rules.
        let brandedBars = [
            "Chocolate Chip - CLIF",
            "Chocolate Chip Cookie Dough - QUEST",
            "Cashew Cookie - LARABAR",
            "Chocolate Sea Salt - RXBAR",
        ]
        for name in brandedBars {
            let unit = primaryUnit(for: name, size: 60)
            XCTAssertEqual(unit, "piece", "'\(name)' should resolve to 'piece' primary; got '\(unit)'")
        }
    }

    func testChocolateDoesNotTriggerLiquidUnits() {
        // Regression: "chocolate" contains "cola" as a substring. Liquid-detection
        // must not false-match and add ml/fl oz to solid chocolate products.
        let chocolates = [
            "Chocolate Almond",
            "Dark Chocolate Chips",
            "Hot Chocolate Mix",  // note: cocoa-based mix, still solid powder
        ]
        for name in chocolates {
            let units = FoodUnit.smartUnits(for: food(name, size: 30))
            XCTAssertFalse(units.contains(where: { $0.label == "fl oz" }),
                           "'\(name)' must not include 'fl oz'; got \(units.map(\.label))")
        }
    }

    func testCocaColaStillTriggersLiquidUnits() {
        // Real cola should still be detected as liquid — "cola" as a word should match.
        let units = FoodUnit.smartUnits(for: food("Coca Cola", size: 330))
        XCTAssertTrue(units.contains(where: { $0.label == "ml" }),
                      "Coca Cola should include 'ml' unit; got \(units.map(\.label))")
    }

    // MARK: - Default Amount (bug #195: Coffee shows 0 cal on quick-add)

    func testDefaultAmountForLiquidsIsServingSize() {
        // Liquid foods with primary unit "ml" (gramsEquivalent=1) must prefill the full
        // serving size, otherwise a default of "1" → 1ml → 0 cal displayed.
        let liquids: [(String, Double, String)] = [
            ("Coffee (black)", 240, "240"),
            ("Whole Milk", 240, "240"),
            ("Orange Juice", 250, "250"),
            ("Coke", 330, "330"),
            ("Beer", 355, "355"),
        ]
        for (name, size, expected) in liquids {
            let f = food(name, size: size)
            let got = FoodUnit.defaultAmount(for: f)
            XCTAssertEqual(got, expected, "'\(name)' default should be \(expected), got \(got)")
        }
    }

    func testDefaultAmountForDiscreteUnitsIsOne() {
        // Discrete units (egg/piece/cup/scoop) should keep default of "1"
        let discrete: [(String, Double)] = [
            ("Whole Egg", 50),
            ("Roti", 40),
            ("Samosa", 60),
            ("Whey Protein", 30),
            ("Basmati Rice", 100),  // cup unit (cupFoods)
        ]
        for (name, size) in discrete {
            let f = food(name, size: size)
            let got = FoodUnit.defaultAmount(for: f)
            XCTAssertEqual(got, "1", "'\(name)' default should be '1', got '\(got)'")
        }
    }

    // MARK: - pieceSizeG override propagates to per-piece labels
    //
    // 2026-05-24 field bug: TJ Chicken Meatballs in the user's DB had
    // `servingSize = 85` (full serving = ~5 meatballs) and primaryUnit()
    // returned FoodUnit("meatball", gramsEquivalent: 85). Reconcile only
    // handled "piece"/"cup"/"tbsp"/"scoop"/"bowl", so per-meatball
    // calories displayed at 5× the real value. These tests pin the
    // resolved per-piece grams for every per-piece label primaryUnit
    // emits — failing here = the bug is back.

    private func resolvedPrimaryGrams(name: String,
                                      servingSize: Double,
                                      pieceSizeG: Double?) -> Double {
        let f = Food(name: name, category: "Test",
                     servingSize: servingSize, servingUnit: "g",
                     calories: 100, pieceSizeG: pieceSizeG)
        return FoodUnit.smartUnits(for: f).first?.gramsEquivalent ?? 0
    }

    func testMeatballPieceSizeGOverridesServingSize() {
        // Reproduces the field bug. servingSize = 85g (5 meatballs at 17g),
        // pieceSizeG = 17 (set by OpenFoodFacts "5 pieces (85g)" parsing).
        let g = resolvedPrimaryGrams(name: "Trader Joe's Chicken Meatballs",
                                     servingSize: 85, pieceSizeG: 17)
        XCTAssertEqual(g, 17, "1 meatball must resolve to pieceSizeG, not servingSize")
    }

    func testMeatballWithoutPieceSizeGFallsBackToServingSize() {
        // Legacy entries (no piecesPerServing parsed) keep the existing
        // behavior so this fix doesn't silently alter old food rows.
        let g = resolvedPrimaryGrams(name: "Plain Meatball",
                                     servingSize: 85, pieceSizeG: nil)
        XCTAssertEqual(g, 85, "Without pieceSizeG, primary unit grams = servingSize")
    }

    func testEggPieceSizeGOverridesServingSize() {
        let g = resolvedPrimaryGrams(name: "Boiled Egg",
                                     servingSize: 100, pieceSizeG: 50)
        XCTAssertEqual(g, 50, "1 egg must resolve to pieceSizeG when set")
    }

    func testIdliPieceSizeGOverridesServingSize() {
        // Indian-food bar: idli typical 30g/piece, serving often 4× (120g).
        let g = resolvedPrimaryGrams(name: "Idli", servingSize: 120, pieceSizeG: 30)
        XCTAssertEqual(g, 30, "1 idli must resolve to pieceSizeG when set")
    }

    func testSamosaPieceSizeGOverridesServingSize() {
        let g = resolvedPrimaryGrams(name: "Samosa", servingSize: 150, pieceSizeG: 50)
        XCTAssertEqual(g, 50, "1 samosa must resolve to pieceSizeG when set")
    }

    func testGramLabelNeverOverriddenByPieceSizeG() {
        // pieceSizeG must NEVER influence the "g" unit's gramsEquivalent
        // (always 1) — that would invert the entire macro math.
        let f = Food(name: "Olive Oil", category: "Test",
                     servingSize: 14, servingUnit: "g",
                     calories: 120, pieceSizeG: 14)
        let units = FoodUnit.smartUnits(for: f)
        let gramsUnit = units.first(where: { $0.label == "g" })
        XCTAssertEqual(gramsUnit?.gramsEquivalent, 1,
                       "'g' unit must always have gramsEquivalent=1 regardless of pieceSizeG")
    }

    func testCupLabelNeverOverriddenByPieceSizeG() {
        // Cup-foods have their own cupSizeG override; pieceSizeG must not
        // bleed in.
        let f = Food(name: "Cooked Rice", category: "Test",
                     servingSize: 158, servingUnit: "g",
                     calories: 200, pieceSizeG: 10) // nonsense piece for rice
        let units = FoodUnit.smartUnits(for: f)
        let cupUnit = units.first(where: { $0.label == "cup" })
        XCTAssertNotEqual(cupUnit?.gramsEquivalent, 10,
                          "'cup' unit must not adopt pieceSizeG")
    }
}

// MARK: - SuspiciousPieceCheck (anomaly tripwire)

final class SuspiciousPieceCheckTests: XCTestCase {

    // Reproduces the 2026-05-24 field bug — TJ Chicken Meatballs at 85g/piece.
    func testMeatballWayHigh_triggers() {
        let range = SuspiciousPieceCheck.suspicious(label: "meatball", gramsEquivalent: 85)
        XCTAssertNotNil(range, "85g/meatball must trip — typical is 12-28g")
    }

    // A slightly larger-than-average meatball must NOT trip (false-positive guard).
    func testMeatballAtBoundary_doesNotTrigger() {
        let range = SuspiciousPieceCheck.suspicious(label: "meatball", gramsEquivalent: 30)
        XCTAssertNil(range, "30g/meatball is plausible — no warning")
    }

    // Foods outside the lookup must never trip — no false positives for
    // unknown labels (would scare users for nothing).
    func testUnknownLabel_neverTriggers() {
        let range = SuspiciousPieceCheck.suspicious(label: "stuffed-paratha-roll", gramsEquivalent: 500)
        XCTAssertNil(range, "Unknown labels must not surface a warning")
    }

    func testIdliFullServingMisMapping_triggers() {
        // Common DB pattern: 4 idlis per serving, ss=120g, but pieceSizeG missing →
        // ServingUnit returns "idli @ 120g" which is 4× too high.
        let range = SuspiciousPieceCheck.suspicious(label: "idli", gramsEquivalent: 120)
        XCTAssertNotNil(range, "120g/idli must trip — typical is 20-45g")
    }

    // Case-insensitive lookup — primaryUnit lowercases labels but ServingInputView
    // displays whatever the unit struct holds, so the check must tolerate either.
    func testLabelLookupIsCaseInsensitive() {
        let range = SuspiciousPieceCheck.suspicious(label: "MEATBALL", gramsEquivalent: 85)
        XCTAssertNotNil(range, "Lookup must be case-insensitive")
    }
}

// MARK: - Field-report weirdness battery (2026-07-10, operator: "good by
// default — user doesn't do math"). Covers #1010/#1011/#1049 + the Rip Van
// wafel barcode case.

extension SmartUnitsGoldSetTests {

    private func unit(_ f: Food) -> FoodUnit? { FoodUnit.smartUnits(for: f).first }

    /// Beverages default to a human cup, never raw ml (#1049 field: "coffee
    /// defaulting to ml").
    func testBeveragesDefaultToCup() {
        let drinks: [(String, Double)] = [
            ("Coffee", 240), ("Black Coffee", 240), ("Coffee (black)", 240),
            ("Chai", 240), ("Green Tea", 240), ("Masala Chai", 240),
            ("Orange Juice", 240), ("Buttermilk", 240),
        ]
        var misses: [String] = []
        for (name, ml) in drinks {
            let f = Food(name: name, category: "Test", servingSize: ml, servingUnit: "ml", calories: 50)
            let u = unit(f)
            if u?.label != "cup" { misses.append("\(name) → \(u?.label ?? "nil")") }
        }
        XCTAssertTrue(misses.isEmpty, "beverages should default to cup: \(misses)")
    }

    /// Milk seeded in ml (244) must be cup, not "244 ml".
    func testMilkDefaultsToCup() {
        let f = Food(name: "Milk (2%)", category: "Dairy", servingSize: 244, servingUnit: "ml", calories: 122)
        XCTAssertEqual(unit(f)?.label, "cup", "milk → cup, got \(unit(f)?.label ?? "nil")")
    }

    /// Scanned products carry the label's real serving — that beats any
    /// name-keyword inference. Rip Van wafel field case: name contains
    /// "Honey" → old code defaulted to 1 tbsp (21g/72cal) for a 33g wafel.
    func testScannedProductServingBeatsNameKeywords() {
        let wafel = Food(name: "Wafels European Snack Honey & Oats - Rip Van",
                         category: "Scanned", servingSize: 33, servingUnit: "g", calories: 342)
        let u = unit(wafel)
        XCTAssertEqual(u?.label, "serving", "scanned wafel → serving, got \(u?.label ?? "nil")")
        XCTAssertEqual(u?.gramsEquivalent ?? 0, 33, accuracy: 0.01, "serving must be the label's 33g")
    }

    /// Plain nuts: primary is the concrete "handful" (#1010 landed
    /// decision — no math), with a per-piece count unit ONE TAP away.
    func testPlainNutsHandfulPrimaryWithCountAvailable() {
        for (name, count) in [("Almonds", "almond"), ("Cashews", "cashew")] {
            let f = Food(name: name, category: "Nuts", servingSize: 28, servingUnit: "g", calories: 160)
            let units = FoodUnit.smartUnits(for: f)
            XCTAssertEqual(units.first?.label, "handful", "\(name) primary → handful")
            XCTAssertTrue(units.contains { $0.label == count }, "\(name) must offer \(count) count")
        }
        // Derivatives must NOT count-default
        let milk = Food(name: "Almond Milk", category: "Dairy", servingSize: 240, servingUnit: "ml", calories: 30)
        XCTAssertNotEqual(FoodUnit.smartUnits(for: milk).first?.label, "almond")
    }

    /// Peanut butter: 1 tbsp must be ~16g (#1011 field: "PB tbsp 2x" — a
    /// 32g-serving seed leaking into the tbsp weight doubles every log).
    func testPeanutButterTbspIsSingleTbsp() {
        let f = Food(name: "Peanut Butter", category: "Spreads", servingSize: 32, servingUnit: "g", calories: 190)
        let units = FoodUnit.smartUnits(for: f)
        guard let tbsp = units.first(where: { $0.label == "tbsp" }) else {
            return XCTFail("peanut butter should offer tbsp: \(units.map(\.label))")
        }
        XCTAssertEqual(tbsp.gramsEquivalent, 16, accuracy: 3, "1 tbsp PB ≈ 16g, got \(tbsp.gramsEquivalent)")
    }

    /// Whole fruits count by the piece.
    func testBananaDefaultsToPiece() {
        let f = Food(name: "Banana", category: "Fruit", servingSize: 118, servingUnit: "g", calories: 105)
        let label = unit(f)?.label ?? ""
        XCTAssertTrue(label == "piece" || label == "banana", "banana → piece, got \(label)")
    }

    /// Rice serves by the cup/bowl, not grams.
    func testCookedRiceDefaultsToCupOrBowl() {
        let f = Food(name: "Rice", category: "Grains", servingSize: 186, servingUnit: "g", calories: 205)
        let label = unit(f)?.label ?? ""
        XCTAssertTrue(label == "cup" || label == "bowl", "rice → cup/bowl, got \(label)")
    }
}

extension SmartUnitsGoldSetTests {
    /// The stored logged portion beats the keyword guesser (#1013: a 150 g
    /// paneer log displayed "1.5 cups").
    func testLoggedPortionBeatsKeywordGuess() {
        var e = FoodEntry(foodName: "Paneer", servingSizeG: 100, servings: 1.5,
                          calories: 265, loggedPortion: "150 g")
        XCTAssertEqual(e.portionText, "150 g")
        e.loggedPortion = nil
        XCTAssertTrue(e.portionText.contains("cup"), "legacy entries keep the keyword fallback")
    }
}
