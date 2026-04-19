import XCTest
@testable import Drift

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
}
